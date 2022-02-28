import Foundation
import SwiftSignalKit
import ForkTelegramInterface

// MARK: - Types

public protocol RequestData {
    var parameters: Parameters { get }
}

public enum NetworkError: Error {
    case network
    case emptyResponse
    case errorStatusCode(statusCode: Int)
    case decodeError(rawData: Data)
}

public enum HttpMethod: String {
    case get = "GET"
    case post = "POST"
    case delete = "DELETE"
}

public enum API {
    public static var apiUrl: String {
        return "https://api.teleton.io/api/v1/"
    }
}

public struct MultipartFileData {
    public let filename: String
    public let fieldName: String
    public let mimeType: MimeType
    public let fileData: Data
    
    public init(
        filename: String,
        fieldName: String,
        mimeType: MimeType,
        fileData: Data
    ) {
        self.filename = filename
        self.fieldName = fieldName
        self.mimeType = mimeType
        self.fileData = fileData
    }
}

public enum MimeType: String {
    case imageJpg = "image/jpg"
}

public final class RequestManager: NSObject {

    public typealias DownloadTaskHandler = (completion: (Result<URL, Error>) -> Void, progressClosure: (Float) -> Void)

    // MARK: - Components

    private let urlSessionConfig: URLSessionConfiguration
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let lock: NSLock
    private let deviceInfo: DeviceInfo
    private let telegramInterfaceStorage: TelegramInterfaceStorage
    private lazy var urlSession = URLSession(configuration: urlSessionConfig,
                                             delegate: self,
                                             delegateQueue: nil)
    private let urlSessionQueueIsBusy = ValuePromise<Bool>(false, ignoreRepeated: true)

    private var downloadTasks: [URLSessionDownloadTask: DownloadTaskHandler] = [:]
    
    private var telegramInterface: TelegramInterface? {
        telegramInterfaceStorage.interface
    }
    
    init(fileManager: FileManager,
         decoder: JSONDecoder,
         lock: NSLock,
         deviceInfo: DeviceInfo,
         urlSessionConfig: URLSessionConfiguration,
         telegramInterfaceStorage: TelegramInterfaceStorage) {
        self.fileManager = fileManager
        self.decoder = decoder
        self.lock = lock
        self.deviceInfo = deviceInfo
        self.urlSessionConfig = urlSessionConfig
        self.telegramInterfaceStorage = telegramInterfaceStorage
    }

    // MARK: - Requests

    public func request<T: Decodable>(
        withMethod: HttpMethod = .get,
        url: URL,
        parameters: Parameters? = nil,
        multipartFiles: [MultipartFileData]? = nil,
        parameterEncoding: ParameterEncoding = JSONEncoding.default,
        authToken: String? = nil,
        additionalHeaders: [String: String] = [:],
        iso8601Date: Bool = false
    ) -> Signal<T, Error> {
        return request(
            withMethod: withMethod,
            url: url,
            parameters: parameters,
            multipartFiles: multipartFiles,
            parameterEncoding: parameterEncoding,
            authToken: authToken,
            additionalHeaders: additionalHeaders
        ) { [decoder] in
            decoder.dateDecodingStrategy = iso8601Date ? iso8601FullDecodingStrategy() : .deferredToDate
            return try decoder.decode(T.self, from: $0 ?? Data())
        }
    }

    public func request(
        withMethod: HttpMethod = .get,
        url: URL,
        parameters: Parameters? = nil,
        parameterEncoding: ParameterEncoding = JSONEncoding.default,
        authToken: String? = nil
    ) -> Signal<Void, Error> {
        return request(
            withMethod: withMethod,
            url: url,
            parameters: parameters,
            parameterEncoding: parameterEncoding,
            authToken: authToken
        ) { _ in () }
    }

    public func request<T>(
        withMethod method: HttpMethod,
        url: URL,
        parameters: Parameters?,
        multipartFiles: [MultipartFileData]? = nil,
        parameterEncoding: ParameterEncoding,
        authToken: String? = nil,
        binanceToken: String? = nil,
        additionalHeaders: [String: String] = [:],
        deserialisationClosure: @escaping (Data?) throws -> T
    ) -> Signal<T, Error> {
        var request: URLRequest
        do {
            request = try parameterEncoding.encode(URLRequest(url: url), with: parameters)
        } catch {
            return .fail(error)
        }

        request.httpMethod = method.rawValue
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        
        if let multipartFiles = multipartFiles {
            let boundary = "Boundary-\(UUID().uuidString)"
            var body = multipartFiles.reduce(Data()) { partialResult, fileData in
                return partialResult + convertFileData(
                    fieldName: fileData.fieldName,
                    fileName: fileData.filename,
                    mimeType: fileData.mimeType.rawValue,
                    fileData: fileData.fileData,
                    using: boundary
                )
            }
            body.appendString("--\(boundary)--")
            request.httpBody = body
            request.allHTTPHeaderFields?["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
        }
        
        deviceInfo.headers(interface: telegramInterface).forEach {
            request.allHTTPHeaderFields?[$0.key] = $0.value
        }
        
        if let authToken = authToken {
            request.allHTTPHeaderFields?["Authorization"] = "Bearer \(authToken)"
        }
        
        additionalHeaders.forEach { k, v in request.allHTTPHeaderFields?[k] = v }
        
        #if DEBUG
        let printableHeaders = (request.allHTTPHeaderFields ?? [:]).map { "\($0) = \($1)" }.joined(separator: "\n")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "empty"
        print("---REQUEST---\n\n🌍 URL:\n\(method.rawValue) \(url.absoluteString)\n🤖 Headers:\n\(printableHeaders)\n⚙️ Body:\n\(body)\n")
        #endif

        return urlSessionQueueIsBusy.get() // We waint until previous url session task is finished so we don't burst the server
        |> filter { $0 == false }
        |> take(1)
        |> beforeNext { [weak self] _ in self?.urlSessionQueueIsBusy.set(true) }
        |> castError(Error.self)
        |> mapToSignal { [urlSession] _ in
            Signal { subscriber in
                let task = urlSession.dataTask(with: request) { data, response, error in
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == NSURLErrorDomain {
                            if [
                                NSURLErrorTimedOut,
                                NSURLErrorResourceUnavailable,
                                NSURLErrorNotConnectedToInternet,
                                NSURLErrorDNSLookupFailed,
                                NSURLErrorCannotFindHost
                            ]
                            .contains(nsError.code) {
                                return subscriber.putError(NetworkError.network)
                            }
                        }
                        return subscriber.putError(error)
                    }

                    guard let response = response, let httpResponse = response as? HTTPURLResponse else {
                        return subscriber.putError(NetworkError.emptyResponse)
                    }

                    guard (200 ... 399).contains(httpResponse.statusCode) else {
                        if let data = data {
                            return subscriber.putError(NetworkError.decodeError(rawData: data))
                        }
                        return subscriber.putError(NetworkError.errorStatusCode(statusCode: httpResponse.statusCode))
                    }

                    #if DEBUG
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("---RESPONSE---\n\nBODY:\n\(responseString)\n")
                    }
                    #endif
                    
                    let decodedData: T
                    do {
                        decodedData = try deserialisationClosure(data)
                        subscriber.putNext(decodedData)
                        subscriber.putCompletion()
                    } catch let decodeError {
                        #if DEBUG
                        print("⚠️ Decode Error: \(decodeError)")
                        #endif
                        if let data = data {
                            subscriber.putError(NetworkError.decodeError(rawData: data))
                        } else {
                            subscriber.putError(decodeError)
                        }
                    }
                }

                task.resume()
                return ActionDisposable {
                    task.cancel()
                }
            }
        }
        |> afterDisposed { [weak self] in self?.urlSessionQueueIsBusy.set(false) }
    }

    public func download(
        from url: URL,
        downloadProgressCallback: @escaping (Float) -> Void = { _ in }
    ) -> Signal<URL, Error> {
        return Signal { [weak self, urlSession, lock] subscriber in
            let task = urlSession.downloadTask(with: url)

            let completion = { (res: Result<URL, Error>) -> Void in
                switch res {
                    case let .success(fileUrl):
                        subscriber.putNext(fileUrl)
                        subscriber.putCompletion()
                    case let .failure(error):
                        subscriber.putError(error)
                }
            }

            lock.lock()
            self?.downloadTasks[task] = (
                completion: completion,
                progressClosure: downloadProgressCallback
            )
            lock.unlock()

            task.resume()
            return ActionDisposable { [weak self] in
                task.cancel(byProducingResumeData: { _ in
                    // TODO: Cache resume data
                })

                lock.lock()
                self?.downloadTasks.removeValue(forKey: task)
                lock.unlock()
            }
        }
    }
    
    // MARK: - Private methods
    
    private func convertFileData(
        fieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        using boundary: String
    ) -> Data {
        var data = Data()

        data.appendString("--\(boundary)\r\n")
        data.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        data.appendString("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        data.appendString("\r\n")
        return data
    }
}

// MARK: - Session delegate

extension RequestManager: URLSessionDownloadDelegate {

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let handlers = getHandlersSafely(for: downloadTask)

        let tempUrl: URL
        do {
            tempUrl = try fileManager.moveFileToTempDir(from: location)
        } catch {
            handlers?.completion(.failure(error))
            return
        }

        handlers?.completion(.success(tempUrl))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error, let downloadTask = task as? URLSessionDownloadTask else { return }

        let handlers = getHandlersSafely(for: downloadTask)
        handlers?.completion(.failure(error))
    }

    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let current = Float(totalBytesWritten)
        let total = Float(totalBytesExpectedToWrite)

        var currentProgress = totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown && totalBytesExpectedToWrite != 0
            ? current / total
            : 0.0

        if currentProgress > 1 {
            currentProgress = 1.0
        } else if currentProgress < 0 {
            currentProgress = 0.0
        }

        let handlers = getHandlersSafely(for: downloadTask)
        handlers?.progressClosure(currentProgress)
    }

    private func getHandlersSafely(for task: URLSessionDownloadTask) -> DownloadTaskHandler? {
        lock.lock()
        defer { lock.unlock() }

        return downloadTasks[task]
    }

}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}

fileprivate func iso8601FullDecodingStrategy() -> JSONDecoder.DateDecodingStrategy {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    return .custom { decoder -> Date in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)

        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        if let date = formatter.date(from: dateStr) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        if let date = formatter.date(from: dateStr) {
            return date
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "")
        )
    }
}
