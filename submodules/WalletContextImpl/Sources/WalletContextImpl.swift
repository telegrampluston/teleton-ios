import Foundation
import UIKit
import AccountContext
import WalletCore
import TelegramCore
import SwiftSignalKit
import DeviceAccess
import Display
import WalletContext
import BuildConfig
import AppBundle
import TelegramPresentationData
import ShareController

private final class FileBackedStorageImpl {
    private let queue: Queue
    private let path: String
    private var data: Data?
    private var subscribers = Bag<(Data?) -> Void>()
    
    init(queue: Queue, path: String) {
        self.queue = queue
        self.path = path
    }
    
    func get() -> Data? {
        if let data = self.data {
            return data
        } else {
            self.data = try? Data(contentsOf: URL(fileURLWithPath: self.path))
            return self.data
        }
    }
    
    func set(data: Data) {
        self.data = data
        do {
            try data.write(to: URL(fileURLWithPath: self.path), options: .atomic)
        } catch let error {
            print("Error writng data: \(error)")
        }
        for f in self.subscribers.copyItems() {
            f(data)
        }
    }
    
    func watch(_ f: @escaping (Data?) -> Void) -> Disposable {
        f(self.get())
        let index = self.subscribers.add(f)
        let queue = self.queue
        return ActionDisposable { [weak self] in
            queue.async {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.subscribers.remove(index)
            }
        }
    }
}

private final class FileBackedStorage {
    private let queue = Queue()
    private let impl: QueueLocalObject<FileBackedStorageImpl>
    
    init(path: String) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return FileBackedStorageImpl(queue: queue, path: path)
        })
    }
    
    func get() -> Signal<Data?, NoError> {
        return Signal { subscriber in
            self.impl.with { impl in
                subscriber.putNext(impl.get())
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
    
    func set(data: Data) -> Signal<Never, NoError> {
        return Signal { subscriber in
            self.impl.with { impl in
                impl.set(data: data)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
    
    func update<T>(_ f: @escaping (Data?) -> (Data, T)) -> Signal<T, NoError> {
        return Signal { subscriber in
            self.impl.with { impl in
                let (data, result) = f(impl.get())
                impl.set(data: data)
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
    
    func watch() -> Signal<Data?, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.watch({ data in
                    subscriber.putNext(data)
                }))
            }
            return disposable
        }
    }
}

private let records = Atomic<[WalletStateRecord]>(value: [])

public final class WalletStorageInterfaceImpl: WalletStorageInterface {
    private let storage: FileBackedStorage
    private let configurationStorage: FileBackedStorage
    
    public init(path: String, configurationPath: String) {
        self.storage = FileBackedStorage(path: path)
        self.configurationStorage = FileBackedStorage(path: configurationPath)
    }
    
    public func watchWalletRecords() -> Signal<[WalletStateRecord], NoError> {
        return self.storage.watch()
        |> map { data -> [WalletStateRecord] in
            guard let data = data else {
                return []
            }
            do {
                return try JSONDecoder().decode(Array<WalletStateRecord>.self, from: data)
            } catch let error {
                print("Error deserializing data: \(error)")
                return []
            }
        }
    }
    
    public func getWalletRecords() -> Signal<[WalletStateRecord], NoError> {
        return self.storage.get()
        |> map { data -> [WalletStateRecord] in
            guard let data = data else {
                return []
            }
            do {
                return try JSONDecoder().decode(Array<WalletStateRecord>.self, from: data)
            } catch let error {
                print("Error deserializing data: \(error)")
                return []
            }
        }
    }
    
    public func updateWalletRecords(_ f: @escaping ([WalletStateRecord]) -> [WalletStateRecord]) -> Signal<[WalletStateRecord], NoError> {
        return self.storage.update { data -> (Data, [WalletStateRecord]) in
            let records: [WalletStateRecord] = data.flatMap {
                try? JSONDecoder().decode(Array<WalletStateRecord>.self, from: $0)
            } ?? []
            let updatedRecords = f(records)
            do {
                let updatedData = try JSONEncoder().encode(updatedRecords)
                return (updatedData, updatedRecords)
            } catch let error {
                print("Error serializing data: \(error)")
                return (Data(), updatedRecords)
            }
        }
    }
    
    fileprivate func mergedLocalWalletConfiguration() -> Signal<MergedLocalWalletConfiguration, NoError> {
        return self.configurationStorage.watch()
        |> map { data -> MergedLocalWalletConfiguration in
            guard let data = data, !data.isEmpty else {
                return .default
            }
            do {
                return try JSONDecoder().decode(MergedLocalWalletConfiguration.self, from: data)
            } catch let error {
                print("Error deserializing data: \(error)")
                return .default
            }
        }
    }
    
    public func localWalletConfiguration() -> Signal<LocalWalletConfiguration, NoError> {
        return self.mergedLocalWalletConfiguration()
        |> mapToSignal { value -> Signal<LocalWalletConfiguration, NoError> in
            return .single(LocalWalletConfiguration(
                mainNet: value.mainNet.configuration,
                testNet: value.testNet.configuration,
                activeNetwork: value.activeNetwork
            ))
        }
        |> distinctUntilChanged
    }
    
    fileprivate func updateMergedLocalWalletConfiguration(
        _ f: @escaping (MergedLocalWalletConfiguration) -> MergedLocalWalletConfiguration
    ) -> Signal<Never, NoError> {
        return self.configurationStorage.update { data -> (Data, Void) in
            do {
                let current: MergedLocalWalletConfiguration?
                if let data = data, !data.isEmpty {
                    current = try? JSONDecoder().decode(MergedLocalWalletConfiguration.self, from: data)
                } else {
                    current = nil
                }
                let updated = f(current ?? .default)
                let updatedData = try JSONEncoder().encode(updated)
                return (updatedData, Void())
            } catch let error {
                print("Error serializing data: \(error)")
                return (Data(), Void())
            }
        }
        |> ignoreValues
    }
}

public final class WalletContextImpl: NSObject, WalletContext, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public var storage: WalletStorageInterface {
        return self.storageImpl
    }
    private let storageImpl: WalletStorageInterfaceImpl
    private let accountContext: AccountContext
    public let tonInstance: TonInstance
    public let keychain: TonKeychain
    public var presentationData: PresentationData
    public let presentationDataSignal: Signal<PresentationData, NoError>
    
    public let supportsCustomConfigurations: Bool = true
    public let termsUrl: String? = nil
    public let feeInfoUrl: String? = nil
    public var inForeground: Signal<Bool, NoError> {
        return accountContext.sharedContext.applicationBindings.applicationInForeground
    }
    
    private var currentImagePickerCompletion: ((UIImage) -> Void)?
    
    private var presentationDataDisposable: Disposable?
    private var botResolveDisposable: Disposable?
    
    private func pushOnMain(_ viewController: ViewController) {
        guard let rootController = accountContext.sharedContext.mainWindow?.viewController as? NavigationController else { return }
        rootController.pushViewController(viewController)
    }
    
    public func getServerSalt() -> Signal<Data, WalletContextGetServerSaltError> {
        return .single(Data())
    }
    
    public func downloadFile(url: URL) -> Signal<Data, WalletDownloadFileError> {
        return download(url: url)
        |> mapError { _ in
            return .generic
        }
    }
    
    public func updateResolvedWalletConfiguration(
        configuration: LocalWalletConfiguration,
        source: LocalWalletConfigurationSource,
        resolvedConfig: String
    ) -> Signal<Never, NoError> {
        return self.storageImpl.updateMergedLocalWalletConfiguration { current in
            var current = current
            current.mainNet.configuration = configuration.mainNet
            current.testNet.configuration = configuration.testNet
            current.activeNetwork = configuration.activeNetwork
            if current.mainNet.configuration.source == source {
                current.mainNet.resolved = ResolvedLocalWalletConfiguration(source: source, value: resolvedConfig)
            }
            if current.testNet.configuration.source == source {
                current.testNet.resolved = ResolvedLocalWalletConfiguration(source: source, value: resolvedConfig)
            }
            return current
        }
    }
    
    public func presentNativeController(_ controller: UIViewController) {
        accountContext.sharedContext.applicationBindings.presentNativeController(controller)
    }
    
    public func idleTimerExtension() -> Disposable {
        return accountContext.sharedContext.applicationBindings.pushIdleTimerExtension()
    }
    
    public func openUrl(_ url: String) {
        return accountContext.sharedContext.openExternalUrl(
            context: accountContext,
            urlContext: .generic,
            url: url,
            forceExternal: true,
            presentationData: presentationData,
            navigationController: nil,
            dismissInput: {}
        )
    }
    
    public func shareUrl(_ url: String) {
        let controller = ShareController(context: accountContext, subject: .url(url))
        accountContext.sharedContext.mainWindow?.present(controller, on: .root)
    }
    
    public func openPlatformSettings() {
        accountContext.sharedContext.applicationBindings.openSettings()
    }
    
    public func authorizeAccessToCamera(completion: @escaping () -> Void) {
        DeviceAccess.authorizeAccess(to: .camera(.qrCode), presentationData: presentationData, present: { [weak self] c, a in
            c.presentationArguments = a
            self?.accountContext.sharedContext.mainWindow?.present(c, on: .root)
        }, openSettings: { [weak self] in
            self?.openPlatformSettings()
        }, { granted in
            guard granted else {
                return
            }
            completion()
        })
    }
    
    public func pickImage(present: @escaping (ViewController) -> Void, completion: @escaping (UIImage) -> Void) {
        self.currentImagePickerCompletion = completion
        
        let pickerController = UIImagePickerController()
        pickerController.delegate = self
        pickerController.allowsEditing = false
        pickerController.mediaTypes = ["public.image"]
        pickerController.sourceType = .photoLibrary
        self.presentNativeController(pickerController)
    }
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let currentImagePickerCompletion = self.currentImagePickerCompletion
        self.currentImagePickerCompletion = nil
        if let image = info[.editedImage] as? UIImage {
            currentImagePickerCompletion?(image)
        } else if let image = info[.originalImage] as? UIImage {
            currentImagePickerCompletion?(image)
        }
        picker.presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.currentImagePickerCompletion = nil
        picker.presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    public func startLinkWallet() {
        botResolveDisposable = (accountContext.engine.peers.resolvePeerByName(name: "teletonapp_bot") |> take(1) |> deliverOnMainQueue)
            .start { [weak self] in
                guard let strongSelf = self, let id = $0?.id else { return }
                let controller = strongSelf.accountContext.sharedContext.makeChatController(
                    context: strongSelf.accountContext,
                    chatLocation: .peer(id),
                    subject: nil,
                    botStart: nil,
                    mode: .standard(previewing: false)
                )
                strongSelf.pushOnMain(controller)
            }
    }
    
    public init(
        storage: WalletStorageInterfaceImpl,
        keysPath: String,
        config: String,
        blockchainName: String,
        accountContext: AccountContext
    ) {
        let _ = try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: keysPath),
            withIntermediateDirectories: true,
            attributes: nil
        )
        self.storageImpl = storage
        
        self.accountContext = accountContext
        self.presentationData = accountContext.sharedContext.currentPresentationData.with { $0 }
        self.presentationDataSignal = accountContext.sharedContext.presentationData
                
        self.tonInstance = TonInstance(
            basePath: keysPath,
            config: config,
            blockchainName: blockchainName,
            proxy: nil
        )
        
        let baseAppBundleId = getAppBundle().bundleIdentifier!
        
        self.keychain = TonKeychain(encryptionPublicKey: {
            return Signal { subscriber in
                BuildConfig.getHardwareEncryptionAvailable(withBaseAppBundleId: baseAppBundleId, completion: { value in
                    subscriber.putNext(value)
                    subscriber.putCompletion()
                })
                return EmptyDisposable
            }
        }, encrypt: { data in
            return Signal { subscriber in
                BuildConfig.encryptApplicationSecret(data, baseAppBundleId: baseAppBundleId, completion: { result, publicKey in
                    if let result = result, let publicKey = publicKey {
                        subscriber.putNext(TonKeychainEncryptedData(publicKey: publicKey, data: result))
                        subscriber.putCompletion()
                    } else {
                        subscriber.putError(.generic)
                    }
                })
                return EmptyDisposable
            }
        }, decrypt: { encryptedData in
            return Signal { subscriber in
                BuildConfig.decryptApplicationSecret(
                    encryptedData.data,
                    publicKey: encryptedData.publicKey,
                    baseAppBundleId: baseAppBundleId,
                    completion: { result, cancelled in
                        if let result = result {
                            subscriber.putNext(result)
                        } else {
                            let error: TonKeychainDecryptDataError
                            if cancelled {
                                error = .cancelled
                            } else {
                                error = .generic
                            }
                            subscriber.putError(error)
                        }
                        subscriber.putCompletion()
                    }
                )
                return EmptyDisposable
            }
        })
                
        super.init()
        
        presentationDataDisposable = presentationDataSignal.start { [weak self] in
            self?.presentationData = $0
        }
    }
    
    deinit {
        botResolveDisposable?.dispose()
        presentationDataDisposable?.dispose()
    }
    
    // MARK: - Fork begin
    public func exploreAddress() {
        guard let network = accountContext.initialResolvedConfigValue?.activeNetwork else {
            return
        }
        var disposable: Disposable?
        disposable = (
            storage.getWalletRecords() |> deliverOnMainQueue
        ).start(next: { [weak self] records in
            guard let record = records.first else {
                return
            }
            switch record.info {
            case .ready(info: let info, exportCompleted: _, state: _):
                let url: String
                if network == .mainNet {
                    url = "https://tonscan.org/address/\(info.address)"
                } else {
                    url = "https://testnet.tonscan.org/address/\(info.address)"
                }
                self?.openUrl(url)
            case .imported(info: _):
                break
            }
            disposable?.dispose()
            disposable = nil
        })
    }
    // MARK: Fork end -
}

private enum DownloadFileError {
    case network
}

private let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.urlCache = nil

    let session = URLSession(configuration: config)
    return session
}()

private func download(url: URL) -> Signal<Data, DownloadFileError> {
    return Signal { subscriber in
        let completed = Atomic<Bool>(value: false)
        let downloadTask = urlSession.downloadTask(with: url, completionHandler: { location, _, error in
            let _ = completed.swap(true)
            if let location = location, let data = try? Data(contentsOf: location) {
                subscriber.putNext(data)
                subscriber.putCompletion()
            } else {
                subscriber.putError(.network)
            }
        })
        downloadTask.resume()
        
        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadTask.cancel()
            }
        }
    }
}

private struct ResolvedLocalWalletConfiguration: Codable, Equatable {
    var source: LocalWalletConfigurationSource
    var value: String
}

private struct MergedLocalBlockchainConfiguration: Codable, Equatable {
    var configuration: WalletCore.LocalBlockchainConfiguration
    var resolved: ResolvedLocalWalletConfiguration?
}

private struct EffectiveWalletConfigurationSource: Equatable {
    let networkName: String
    let source: LocalWalletConfigurationSource
}

private struct MergedLocalWalletConfiguration: Codable, Equatable {
    var mainNet: MergedLocalBlockchainConfiguration
    var testNet: MergedLocalBlockchainConfiguration
    var activeNetwork: LocalWalletConfiguration.ActiveNetwork
    
    var effective: EffectiveWalletConfiguration? {
        switch self.activeNetwork {
        case .mainNet:
            if let resolved = self.mainNet.resolved, resolved.source == self.mainNet.configuration.source {
                return EffectiveWalletConfiguration(
                    networkName: self.mainNet.configuration.customId ?? "mainnet",
                    config: resolved.value,
                    activeNetwork: .mainNet
                )
            } else {
                return nil
            }
        case .testNet:
            if let resolved = self.testNet.resolved, resolved.source == self.testNet.configuration.source {
                return EffectiveWalletConfiguration(
                    networkName: self.testNet.configuration.customId ?? "testnet2",
                    config: resolved.value,
                    activeNetwork: .testNet
                )
            } else {
                return nil
            }
        }
    }
    
    var effectiveSource: EffectiveWalletConfigurationSource {
        switch self.activeNetwork {
        case .mainNet:
            return EffectiveWalletConfigurationSource(
                networkName: self.mainNet.configuration.customId ?? "mainnet",
                source: self.mainNet.configuration.source
            )
        case .testNet:
            return EffectiveWalletConfigurationSource(
                networkName: self.testNet.configuration.customId ?? "testnet2",
                source: self.testNet.configuration.source
            )
        }
    }
}

private extension MergedLocalWalletConfiguration {
    static var `default`: MergedLocalWalletConfiguration {
        return MergedLocalWalletConfiguration(
            mainNet: MergedLocalBlockchainConfiguration(
                configuration: LocalBlockchainConfiguration(
                    source: .url("https://ton.org/global-config-wallet.json"),
                    customId: "mainnet"
                ),
                resolved: nil
            ),
            testNet: MergedLocalBlockchainConfiguration(
                configuration: LocalBlockchainConfiguration(
                    source: .url("https://newton-blockchain.github.io/testnet-global.config.json"),
                    customId: "testnet"
                ),
                resolved: nil
            ),
            activeNetwork: .mainNet
        )
    }
}

public typealias InitialConfigSignal = Signal<EffectiveWalletConfiguration?, NoError>

public func initialConfig(storage: WalletStorageInterfaceImpl) -> InitialConfigSignal {
    return storage.mergedLocalWalletConfiguration()
    |> take(1)
    |> mapToSignal { configuration -> Signal<EffectiveWalletConfiguration?, NoError> in
        if let effective = configuration.effective {
            return .single(effective)
        } else {
            return .single(nil)
        }
    }
}

public typealias UpdatedConfigSignal = Signal<(source: LocalWalletConfigurationSource, blockchainName: String, blockchainNetwork: LocalWalletConfiguration.ActiveNetwork, config: String), NoError>

public func updatedConfig(storage: WalletStorageInterfaceImpl) -> UpdatedConfigSignal {
    return storage.mergedLocalWalletConfiguration()
    |> mapToSignal { configuration -> UpdatedConfigSignal in
        switch configuration.effectiveSource.source {
        case let .url(url):
            guard let parsedUrl = URL(string: url) else {
                return .complete()
            }
            return download(url: parsedUrl)
            |> retry(1.0, maxDelay: 5.0, onQueue: .mainQueue())
            |> mapToSignal { data -> UpdatedConfigSignal in
                if let string = String(data: data, encoding: .utf8) {
                    return .single((
                        source: configuration.effectiveSource.source,
                        blockchainName: configuration.effectiveSource.networkName,
                        blockchainNetwork: configuration.activeNetwork, config: string
                    ))
                } else {
                    return .complete()
                }
            }
        case let .string(string):
            return .single((
                source: configuration.effectiveSource.source,
                blockchainName: configuration.effectiveSource.networkName,
                blockchainNetwork: configuration.activeNetwork,
                config: string
            ))
        }
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        if lhs.0 != rhs.0 {
            return false
        }
        if lhs.1 != rhs.1 {
            return false
        }
        if lhs.2 != rhs.2 {
            return false
        }
        if lhs.3 != rhs.3 {
            return false
        }
        return true
    })
    |> afterNext { source, _, _, config in
        let _ = storage.updateMergedLocalWalletConfiguration({ current in
            var current = current
            if current.mainNet.configuration.source == source {
                current.mainNet.resolved = ResolvedLocalWalletConfiguration(source: source, value: config)
            }
            if current.testNet.configuration.source == source {
                current.testNet.resolved = ResolvedLocalWalletConfiguration(source: source, value: config)
            }
            return current
        }).start()
    }
}

public func resolvedInitialConfig(
    storage: WalletStorageInterfaceImpl,
    initialConfigValue: InitialConfigSignal,
    updatedConfigValue: UpdatedConfigSignal
) -> Signal<EffectiveWalletConfiguration, NoError> {
    return initialConfigValue
    |> mapToSignal { value -> Signal<EffectiveWalletConfiguration, NoError> in
        if let value = value {
            return .single(value)
        } else {
            return Signal { subscriber in
                let update = updatedConfigValue.start()
                let disposable = (storage.mergedLocalWalletConfiguration()
                |> mapToSignal { configuration -> Signal<EffectiveWalletConfiguration, NoError> in
                    if let effective = configuration.effective {
                        return .single(effective)
                    } else {
                        return .complete()
                    }
                }
                |> take(1)).start(next: { next in
                    subscriber.putNext(next)
                }, completed: {
                    subscriber.putCompletion()
                })
                
                return ActionDisposable {
                    update.dispose()
                    disposable.dispose()
                }
            }
        }
    }
}


