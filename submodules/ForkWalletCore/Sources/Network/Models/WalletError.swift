import Foundation
import ForkNetwork

public enum WalletErrorCode: String, Decodable {
    case NO_CONNECTION
    case ERR_UNKNOWN_SERVER_ERROR
    case ERR_WALLET_DOESNT_EXIST
}

public struct WalletError: LocalizedError, Decodable, Equatable {
    
    // MARK: - Public properties
    public let code: WalletErrorCode?
    public static let unknown = WalletError(message: "Unknown error")
    
    public var errorDescription: String? {
        return errorMessage
    }
    
    public var message: String {
        errorDescription ?? localizedDescription
    }

    // MARK: - Lifecycle
    
    public init(message: String, code: WalletErrorCode? = nil) {
        self.errorMessage = message
        self.code = code
    }
    
    // MARK: - Private properties
    
    private let errorMessage: String
    
    // MARK: - Lifecycle
    
    public init(error: Error) {
        var message = "\(String(describing: type(of: error))).\(String(describing: error)) (code \((error as NSError).code))"
        var code: WalletErrorCode?
        if let networkError = error as? NetworkError {
            switch networkError {
            case .decodeError(let rawData):
                let jsonDecoder = JSONDecoder()
                if let parsedError = try? jsonDecoder.decode(WalletError.self, from: rawData) {
                    message = parsedError.message
                    code = parsedError.code
                }
            case .network:
                code = .NO_CONNECTION
            case _: break
            }
        }
        self.errorMessage = message
        self.code = code
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.errorMessage = try container.decode(String.self, forKey: .detail)
        do {
            self.code = try container.decode(WalletErrorCode.self, forKey: .code)
        } catch {
            self.code = .ERR_UNKNOWN_SERVER_ERROR
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case detail
        case code
    }
    
}
