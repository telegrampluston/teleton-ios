import Foundation
import SwiftSignalKit
import UIKit
import Postbox
import TelegramCore
import Display
import DeviceAccess
import TelegramPresentationData
import AccountContext
import LiveLocationManager
import TemporaryCachedPeerDataManager
import PhoneNumberFormat
import TelegramUIPreferences
import TelegramVoip
import TelegramCallsUI
import TelegramBaseController
import AsyncDisplayKit
import PresentationDataUtils
import MeshAnimationCache
// MARK: - Fork Begin
import WalletUI
import WalletCore
import WalletContext
import WalletContextImpl
import EasyDi
// MARK: - Fork End

private final class DeviceSpecificContactImportContext {
    let disposable = MetaDisposable()
    var reference: DeviceContactBasicDataWithReference?
    
    init() {
    }
    
    deinit {
        self.disposable.dispose()
    }
}

private final class DeviceSpecificContactImportContexts {
    private let queue: Queue
    
    private var contexts: [PeerId: DeviceSpecificContactImportContext] = [:]
    
    init(queue: Queue) {
        self.queue = queue
    }
    
    deinit {
        assert(self.queue.isCurrent())
    }
    
    func update(account: Account, deviceContactDataManager: DeviceContactDataManager, references: [PeerId: DeviceContactBasicDataWithReference]) {
        var validIds = Set<PeerId>()
        for (peerId, reference) in references {
            validIds.insert(peerId)
            
            let context: DeviceSpecificContactImportContext
            if let current = self.contexts[peerId] {
                context = current
            } else {
                context = DeviceSpecificContactImportContext()
                self.contexts[peerId] = context
            }
            if context.reference != reference {
                context.reference = reference
                
                let key: PostboxViewKey = .basicPeer(peerId)
                let signal = account.postbox.combinedView(keys: [key])
                |> map { view -> String? in
                    if let user = (view.views[key] as? BasicPeerView)?.peer as? TelegramUser {
                        return user.phone
                    } else {
                        return nil
                    }
                }
                |> distinctUntilChanged
                |> mapToSignal { phone -> Signal<Never, NoError> in
                    guard let phone = phone else {
                        return .complete()
                    }
                    var found = false
                    let formattedPhone = formatPhoneNumber(phone)
                    for number in reference.basicData.phoneNumbers {
                        if formatPhoneNumber(number.value) == formattedPhone {
                            found = true
                            break
                        }
                    }
                    if !found {
                        return deviceContactDataManager.appendPhoneNumber(DeviceContactPhoneNumberData(label: "_$!<Mobile>!$_", value: formattedPhone), to: reference.stableId)
                        |> ignoreValues
                    } else {
                        return .complete()
                    }
                }
                context.disposable.set(signal.start())
            }
        }
        
        var removeIds: [PeerId] = []
        for peerId in self.contexts.keys {
            if !validIds.contains(peerId) {
                removeIds.append(peerId)
            }
        }
        for peerId in removeIds {
            self.contexts.removeValue(forKey: peerId)
        }
    }
}

public final class AccountContextImpl: AccountContext {
    public let sharedContextImpl: SharedAccountContextImpl
    public var sharedContext: SharedAccountContext {
        return self.sharedContextImpl
    }
    public let account: Account
    public let engine: TelegramEngine
    // MARK: - Fork Begin
    public var diContext = DIContext() // Fork. This context can be set here from outside (SharedAccountContext).
    public let walletContext = Atomic<WalletContext?>(value: nil)
    public var walletContextSignal: Signal<WalletContext, NoError> {
        walletContextPromise.get()
    }
    private let updatedConfigValue: UpdatedConfigSignal
    private let initialResolvedConfig = Atomic<EffectiveWalletConfiguration?>(value: nil)
    private let walletContextPromise = Promise<WalletContext>()
    private let walletDisposableSet = DisposableSet()
    public var initialResolvedConfigValue: EffectiveWalletConfiguration? {
        initialResolvedConfig.with { $0 }
    }
    // MARK: - Fork End
    
    public let fetchManager: FetchManager
    public let prefetchManager: PrefetchManager?
    
    public var keyShortcutsController: KeyShortcutsController?
    
    public let downloadedMediaStoreManager: DownloadedMediaStoreManager
    
    public let liveLocationManager: LiveLocationManager?
    public let peersNearbyManager: PeersNearbyManager?
    public let wallpaperUploadManager: WallpaperUploadManager?
    private let themeUpdateManager: ThemeUpdateManager?
    
    public let peerChannelMemberCategoriesContextsManager = PeerChannelMemberCategoriesContextsManager()
    
    public let currentLimitsConfiguration: Atomic<LimitsConfiguration>
    private let _limitsConfiguration = Promise<LimitsConfiguration>()
    public var limitsConfiguration: Signal<LimitsConfiguration, NoError> {
        return self._limitsConfiguration.get()
    }
    
    public var currentContentSettings: Atomic<ContentSettings>
    private let _contentSettings = Promise<ContentSettings>()
    public var contentSettings: Signal<ContentSettings, NoError> {
        return self._contentSettings.get()
    }
    
    public var currentAppConfiguration: Atomic<AppConfiguration>
    private let _appConfiguration = Promise<AppConfiguration>()
    public var appConfiguration: Signal<AppConfiguration, NoError> {
        return self._appConfiguration.get()
    }
    
    public var watchManager: WatchManager?
    
    private var storedPassword: (String, CFAbsoluteTime, SwiftSignalKit.Timer)?
    private var limitsConfigurationDisposable: Disposable?
    private var contentSettingsDisposable: Disposable?
    private var appConfigurationDisposable: Disposable?
    
    private let deviceSpecificContactImportContexts: QueueLocalObject<DeviceSpecificContactImportContexts>
    private var managedAppSpecificContactsDisposable: Disposable?
    
    private var experimentalUISettingsDisposable: Disposable?
    
    public let cachedGroupCallContexts: AccountGroupCallContextCache
    public let meshAnimationCache: MeshAnimationCache
    
    public init(sharedContext: SharedAccountContextImpl, account: Account, limitsConfiguration: LimitsConfiguration, contentSettings: ContentSettings, appConfiguration: AppConfiguration, temp: Bool = false)
    {
        self.sharedContextImpl = sharedContext
        self.account = account
        self.engine = TelegramEngine(account: account)
        
        self.downloadedMediaStoreManager = DownloadedMediaStoreManagerImpl(postbox: account.postbox, accountManager: sharedContext.accountManager)
        
        if let locationManager = self.sharedContextImpl.locationManager {
            self.liveLocationManager = LiveLocationManagerImpl(engine: self.engine, locationManager: locationManager, inForeground: sharedContext.applicationBindings.applicationInForeground)
        } else {
            self.liveLocationManager = nil
        }
        self.fetchManager = FetchManagerImpl(postbox: account.postbox, storeManager: self.downloadedMediaStoreManager)
        if sharedContext.applicationBindings.isMainApp && !temp {
            self.prefetchManager = PrefetchManagerImpl(sharedContext: sharedContext, account: account, engine: self.engine, fetchManager: self.fetchManager)
            self.wallpaperUploadManager = WallpaperUploadManagerImpl(sharedContext: sharedContext, account: account, presentationData: sharedContext.presentationData)
            self.themeUpdateManager = ThemeUpdateManagerImpl(sharedContext: sharedContext, account: account)
        } else {
            self.prefetchManager = nil
            self.wallpaperUploadManager = nil
            self.themeUpdateManager = nil
        }
        
        if let locationManager = self.sharedContextImpl.locationManager, sharedContext.applicationBindings.isMainApp && !temp {
            self.peersNearbyManager = PeersNearbyManagerImpl(account: account, engine: self.engine, locationManager: locationManager, inForeground: sharedContext.applicationBindings.applicationInForeground)
        } else {
            self.peersNearbyManager = nil
        }
        
        self.cachedGroupCallContexts = AccountGroupCallContextCacheImpl()
        self.meshAnimationCache = MeshAnimationCache(mediaBox: account.postbox.mediaBox)
        
        let updatedLimitsConfiguration = account.postbox.preferencesView(keys: [PreferencesKeys.limitsConfiguration])
        |> map { preferences -> LimitsConfiguration in
            return preferences.values[PreferencesKeys.limitsConfiguration]?.get(LimitsConfiguration.self) ?? LimitsConfiguration.defaultValue
        }
        
        self.currentLimitsConfiguration = Atomic(value: limitsConfiguration)
        self._limitsConfiguration.set(.single(limitsConfiguration) |> then(updatedLimitsConfiguration))
        
        let currentLimitsConfiguration = self.currentLimitsConfiguration
        self.limitsConfigurationDisposable = (self._limitsConfiguration.get()
        |> deliverOnMainQueue).start(next: { value in
            let _ = currentLimitsConfiguration.swap(value)
        })
        
        let updatedContentSettings = getContentSettings(postbox: account.postbox)
        self.currentContentSettings = Atomic(value: contentSettings)
        self._contentSettings.set(.single(contentSettings) |> then(updatedContentSettings))
        
        let currentContentSettings = self.currentContentSettings
        self.contentSettingsDisposable = (self._contentSettings.get()
        |> deliverOnMainQueue).start(next: { value in
            let _ = currentContentSettings.swap(value)
        })
        
        let updatedAppConfiguration = getAppConfiguration(postbox: account.postbox)
        self.currentAppConfiguration = Atomic(value: appConfiguration)
        self._appConfiguration.set(.single(appConfiguration) |> then(updatedAppConfiguration))
        
        let currentAppConfiguration = self.currentAppConfiguration
        self.appConfigurationDisposable = (self._appConfiguration.get()
        |> deliverOnMainQueue).start(next: { value in
            let _ = currentAppConfiguration.swap(value)
        })
        
        let queue = Queue()
        self.deviceSpecificContactImportContexts = QueueLocalObject(queue: queue, generate: {
            return DeviceSpecificContactImportContexts(queue: queue)
        })
        
        if let contactDataManager = sharedContext.contactDataManager {
            let deviceSpecificContactImportContexts = self.deviceSpecificContactImportContexts
            self.managedAppSpecificContactsDisposable = (contactDataManager.appSpecificReferences()
            |> deliverOn(queue)).start(next: { appSpecificReferences in
                deviceSpecificContactImportContexts.with { context in
                    context.update(account: account, deviceContactDataManager: contactDataManager, references: appSpecificReferences)
                }
            })
        }
        
        account.callSessionManager.updateVersions(versions: PresentationCallManagerImpl.voipVersions(includeExperimental: true, includeReference: true).map { version, supportsVideo -> CallSessionManagerImplementationVersion in
            CallSessionManagerImplementationVersion(version: version, supportsVideo: supportsVideo)
        })
        // MARK: - Fork Begin
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        #if DEBUG
        print("Starting with \(documentsPath)")
        #endif
        let peerId = account.peerId.id._internalGetInt64Value()
        let storage = WalletStorageInterfaceImpl(
            path: documentsPath + "/\(peerId)_data",
            configurationPath: documentsPath + "/\(peerId)_configuration_v2"
        )
        let keysPath = documentsPath + "/\(peerId)_keys"
        let initialConfigValue = initialConfig(storage: storage)
        let updatedConfigValue = updatedConfig(storage: storage)
        let resolvedInitialConfig = resolvedInitialConfig(storage: storage, initialConfigValue: initialConfigValue, updatedConfigValue: updatedConfigValue)
        self.updatedConfigValue = updatedConfigValue
        let walletConfigDisposable = resolvedInitialConfig.start(next: { [weak self] in
            guard let strongSelf = self else { return }
            let walletContext = WalletContextImpl(
                storage: storage,
                keysPath: keysPath,
                config: $0.config,
                blockchainName: $0.networkName,
                accountContext: strongSelf
            )
            _ = strongSelf.initialResolvedConfig.swap($0)
            _ = strongSelf.walletContext.swap(walletContext)
            strongSelf.walletContextPromise.set(.single(walletContext))
        })
        walletDisposableSet.add(walletConfigDisposable)
        // MARK: - Fork End
    }
    
    deinit {
        self.limitsConfigurationDisposable?.dispose()
        self.managedAppSpecificContactsDisposable?.dispose()
        self.contentSettingsDisposable?.dispose()
        self.appConfigurationDisposable?.dispose()
        self.experimentalUISettingsDisposable?.dispose()
        // MARK: - Fork Begin
        self.walletDisposableSet.dispose()
        // MARK: - Fork End
    }
    
    public func storeSecureIdPassword(password: String) {
        self.storedPassword?.2.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: 1.0 * 60.0 * 60.0, repeat: false, completion: { [weak self] in
            self?.storedPassword = nil
        }, queue: Queue.mainQueue())
        self.storedPassword = (password, CFAbsoluteTimeGetCurrent(), timer)
        timer.start()
    }
    
    public func getStoredSecureIdPassword() -> String? {
        if let (password, timestamp, timer) = self.storedPassword {
            if CFAbsoluteTimeGetCurrent() > timestamp + 1.0 * 60.0 * 60.0 {
                timer.invalidate()
                self.storedPassword = nil
            }
            return password
        } else {
            return nil
        }
    }
    
    public func chatLocationInput(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>) -> ChatLocationInput {
        switch location {
        case let .peer(peerId):
            return .peer(peerId)
        case let .replyThread(data):
            let context = chatLocationContext(holder: contextHolder, account: self.account, data: data)
            return .external(data.messageId.peerId, makeMessageThreadId(data.messageId), context.state)
        }
    }
    
    public func chatLocationOutgoingReadState(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>) -> Signal<MessageId?, NoError> {
        switch location {
        case .peer:
            return .single(nil)
        case let .replyThread(data):
            let context = chatLocationContext(holder: contextHolder, account: self.account, data: data)
            return context.maxReadOutgoingMessageId
        }
    }

    public func chatLocationUnreadCount(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>) -> Signal<Int, NoError> {
        switch location {
        case let .peer(peerId):
            let unreadCountsKey: PostboxViewKey = .unreadCounts(items: [.peer(peerId), .total(nil)])
            return self.account.postbox.combinedView(keys: [unreadCountsKey])
            |> map { views in
                var unreadCount: Int32 = 0

                if let view = views.views[unreadCountsKey] as? UnreadMessageCountsView {
                    if let count = view.count(for: .peer(peerId)) {
                        unreadCount = count
                    }
                }

                return Int(unreadCount)
            }
        case let .replyThread(data):
            let context = chatLocationContext(holder: contextHolder, account: self.account, data: data)
            return context.unreadCount
        }
    }
    
    public func applyMaxReadIndex(for location: ChatLocation, contextHolder: Atomic<ChatLocationContextHolder?>, messageIndex: MessageIndex) {
        switch location {
        case .peer:
            let _ = self.engine.messages.applyMaxReadIndexInteractively(index: messageIndex).start()
        case let .replyThread(data):
            let context = chatLocationContext(holder: contextHolder, account: self.account, data: data)
            context.applyMaxReadIndex(messageIndex: messageIndex)
        }
    }
    
    public func scheduleGroupCall(peerId: PeerId) {
        let _ = self.sharedContext.callManager?.scheduleGroupCall(context: self, peerId: peerId, endCurrentIfAny: true)
    }
    
    public func joinGroupCall(peerId: PeerId, invite: String?, requestJoinAsPeerId: ((@escaping (PeerId?) -> Void) -> Void)?, activeCall: EngineGroupCallDescription) {
        let callResult = self.sharedContext.callManager?.joinGroupCall(context: self, peerId: peerId, invite: invite, requestJoinAsPeerId: requestJoinAsPeerId, initialCall: activeCall, endCurrentIfAny: false)
        if let callResult = callResult, case let .alreadyInProgress(currentPeerId) = callResult {
            if currentPeerId == peerId {
                self.sharedContext.navigateToCurrentCall()
            } else {
                let _ = (self.account.postbox.transaction { transaction -> (Peer?, Peer?) in
                    return (transaction.getPeer(peerId), currentPeerId.flatMap(transaction.getPeer))
                }
                |> deliverOnMainQueue).start(next: { [weak self] peer, current in
                    guard let strongSelf = self else {
                        return
                    }
                    guard let peer = peer else {
                        return
                    }
                    let presentationData = strongSelf.sharedContext.currentPresentationData.with { $0 }
                    if let current = current {
                        if current is TelegramChannel || current is TelegramGroup {
                            let title: String
                            let text: String
                            if let channel = current as? TelegramChannel, case .broadcast = channel.info {
                                title = presentationData.strings.Call_LiveStreamInProgressTitle
                                text = presentationData.strings.Call_LiveStreamInProgressMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string
                            } else {
                                title = presentationData.strings.Call_VoiceChatInProgressTitle
                                text = presentationData.strings.Call_VoiceChatInProgressMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string
                            }

                            strongSelf.sharedContext.mainWindow?.present(textAlertController(context: strongSelf, title: title, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                                guard let strongSelf = self else {
                                    return
                                }
                                let _ = strongSelf.sharedContext.callManager?.joinGroupCall(context: strongSelf, peerId: peer.id, invite: invite, requestJoinAsPeerId: requestJoinAsPeerId, initialCall: activeCall, endCurrentIfAny: true)
                            })]), on: .root)
                        } else {
                            let text: String
                            if let channel = peer as? TelegramChannel, case .broadcast = channel.info {
                                text = presentationData.strings.Call_CallInProgressLiveStreamMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string
                            } else {
                                text = presentationData.strings.Call_CallInProgressVoiceChatMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string
                            }
                            strongSelf.sharedContext.mainWindow?.present(textAlertController(context: strongSelf, title: presentationData.strings.Call_CallInProgressTitle, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                                guard let strongSelf = self else {
                                    return
                                }
                                let _ = strongSelf.sharedContext.callManager?.joinGroupCall(context: strongSelf, peerId: peer.id, invite: invite, requestJoinAsPeerId: requestJoinAsPeerId, initialCall: activeCall, endCurrentIfAny: true)
                            })]), on: .root)
                        }
                    } else {
                        strongSelf.sharedContext.mainWindow?.present(textAlertController(context: strongSelf, title: presentationData.strings.Call_CallInProgressTitle, text: presentationData.strings.Call_ExternalCallInProgressMessage, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                        })]), on: .root)
                    }
                })
            }
        }
    }
    
    public func requestCall(peerId: PeerId, isVideo: Bool, completion: @escaping () -> Void) {
        guard let callResult = self.sharedContext.callManager?.requestCall(context: self, peerId: peerId, isVideo: isVideo, endCurrentIfAny: false) else {
            return
        }
        
        if case let .alreadyInProgress(currentPeerId) = callResult {
            if currentPeerId == peerId {
                completion()
                self.sharedContext.navigateToCurrentCall()
            } else {
                let _ = (self.account.postbox.transaction { transaction -> (Peer?, Peer?) in
                    return (transaction.getPeer(peerId), currentPeerId.flatMap(transaction.getPeer))
                }
                |> deliverOnMainQueue).start(next: { [weak self] peer, current in
                    guard let strongSelf = self else {
                        return
                    }
                    guard let peer = peer else {
                        return
                    }
                    let presentationData = strongSelf.sharedContext.currentPresentationData.with { $0 }
                    if let current = current {
                        if current is TelegramChannel || current is TelegramGroup {
                            let text: String
                            if let channel = current as? TelegramChannel, case .broadcast = channel.info {
                                text = presentationData.strings.Call_LiveStreamInProgressCallMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string
                            } else {
                                text = presentationData.strings.Call_VoiceChatInProgressCallMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string
                            }
                            strongSelf.sharedContext.mainWindow?.present(textAlertController(context: strongSelf, title: presentationData.strings.Call_VoiceChatInProgressTitle, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                                guard let strongSelf = self else {
                                    return
                                }
                                let _ = strongSelf.sharedContext.callManager?.requestCall(context: strongSelf, peerId: peerId, isVideo: isVideo, endCurrentIfAny: true)
                                completion()
                            })]), on: .root)
                        } else {
                            strongSelf.sharedContext.mainWindow?.present(textAlertController(context: strongSelf, title: presentationData.strings.Call_CallInProgressTitle, text: presentationData.strings.Call_CallInProgressMessage(EnginePeer(current).compactDisplayTitle, EnginePeer(peer).compactDisplayTitle).string, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {}), TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                                guard let strongSelf = self else {
                                    return
                                }
                                let _ = strongSelf.sharedContext.callManager?.requestCall(context: strongSelf, peerId: peerId, isVideo: isVideo, endCurrentIfAny: true)
                                completion()
                            })]), on: .root)
                        }
                    } else if let strongSelf = self {
                        strongSelf.sharedContext.mainWindow?.present(textAlertController(context: strongSelf, title: presentationData.strings.Call_CallInProgressTitle, text: presentationData.strings.Call_ExternalCallInProgressMessage, actions: [TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: {
                        })]), on: .root)
                    }
                })
            }
        } else {
            completion()
        }
    }
    // MARK: - Fork Begin
    public func rebuildDIContextSingletonsStorage() {
        diContext.destroySingletons()
    }
    public func openWallet() {
        let theme = sharedContext.currentPresentationData.with { $0 }.theme
        var cancelAction: (() -> Void)? = nil
        let loadingVC = OverlayStatusController(
            theme: theme,
            type: .loading(cancelled: {
                cancelAction?()
            })
        )
        presentOnMain(loadingVC)
        let disposable = (walletContextSignal |> take(1) |> deliverOnMainQueue).start(
            next: { [weak self, weak loadingVC] in
                loadingVC?.dismiss()
                guard
                    let updatedConfigValue = self?.updatedConfigValue,
                    let initialResolvedConfig = self?.initialResolvedConfig.with({ $0 }) else {
                    return
                }
                self?.startWatchingWalletRecordsAndStartWhenReady(initialResolvedConfig, updatedConfigValue, $0)
            })
        walletDisposableSet.add(disposable)
        cancelAction = { [weak loadingVC] in
            disposable.dispose()
            loadingVC?.dismiss()
        }
    }
    private func startWatchingWalletRecordsAndStartWhenReady(
        _ initialResolvedConfig: EffectiveWalletConfiguration,
        _ updatedConfigValue: UpdatedConfigSignal,
        _ walletContext: WalletContext
    ) {
        let disposable = (combineLatest(
            walletContext.storage.getWalletRecords(),
            walletContext.keychain.encryptionPublicKey()
        ) |> deliverOnMainQueue)
            .start(next: { [weak self] records, publicKey in
                guard let strongSelf = self else { return }
                if let record = records.first {
                    if let publicKey = publicKey {
                        let recordPublicKey: Data
                        switch record.info {
                        case let .ready(info, _, _):
                            recordPublicKey = info.encryptedSecret.publicKey
                        case let .imported(info):
                            recordPublicKey = info.encryptedSecret.publicKey
                        }
                        if recordPublicKey == publicKey {
                            switch record.info {
                            case let .ready(info, exportCompleted, _):
                                if exportCompleted {
                                    let infoScreen = WalletInfoScreen(
                                        context: walletContext,
                                        walletInfo: info,
                                        blockchainNetwork: initialResolvedConfig.activeNetwork,
                                        enableDebugActions: false
                                    )
                                    strongSelf.beginWalletWithController(infoScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                                    /* Not sure yet whether it will work now, I think we need to rewrite that
                                    if let url = launchOptions?[UIApplication.LaunchOptionsKey.url] as? URL {
                                        let walletUrl = parseWalletUrl(url)
                                        var randomId: Int64 = 0
                                        arc4random_buf(&randomId, 8)
                                        let sendScreen = walletSendScreen(context: walletContext, randomId: randomId, walletInfo: info, blockchainNetwork: initialResolvedConfig.activeNetwork, address: walletUrl?.address, amount: walletUrl?.amount, comment: walletUrl?.comment)
                                        navigationController.pushViewController(sendScreen)
                                    }
                                    */
                                } else {
                                    let createdScreen = WalletSplashScreen(
                                        context: walletContext,
                                        blockchainNetwork: initialResolvedConfig.activeNetwork,
                                        mode: .created(walletInfo: info, words: nil),
                                        walletCreatedPreloadState: nil
                                    )
                                    strongSelf.beginWalletWithController(createdScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                                }
                            case let .imported(info):
                                let createdScreen = WalletSplashScreen(
                                    context: walletContext,
                                    blockchainNetwork: initialResolvedConfig.activeNetwork,
                                    mode: .successfullyImported(importedInfo: info),
                                    walletCreatedPreloadState: nil
                                )
                                strongSelf.beginWalletWithController(createdScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                            }
                        } else {
                            let splashScreen = WalletSplashScreen(
                                context: walletContext,
                                blockchainNetwork: initialResolvedConfig.activeNetwork,
                                mode: .secureStorageReset(.changed),
                                walletCreatedPreloadState: nil
                            )
                            strongSelf.beginWalletWithController(splashScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                        }
                    } else {
                        let splashScreen = WalletSplashScreen(
                            context: walletContext,
                            blockchainNetwork: initialResolvedConfig.activeNetwork,
                            mode: WalletSplashMode.secureStorageReset(.notAvailable),
                            walletCreatedPreloadState: nil
                        )
                        strongSelf.beginWalletWithController(splashScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                    }
                } else {
                    if publicKey != nil {
                        let splashScreen = WalletSplashScreen(
                            context: walletContext,
                            blockchainNetwork: initialResolvedConfig.activeNetwork,
                            mode: .intro,
                            walletCreatedPreloadState: nil
                        )
                        strongSelf.beginWalletWithController(splashScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                    } else {
                        let splashScreen = WalletSplashScreen(
                            context: walletContext,
                            blockchainNetwork: initialResolvedConfig.activeNetwork,
                            mode: .secureStorageNotAvailable,
                            walletCreatedPreloadState: nil
                        )
                        strongSelf.beginWalletWithController(splashScreen, initialResolvedConfig, updatedConfigValue, walletContext)
                    }
                }
        })
        walletDisposableSet.add(disposable)
    }
    private func beginWalletWithController(
        _ controller: ViewController,
        _ initialResolvedConfig: EffectiveWalletConfiguration,
        _ updatedConfigValue: UpdatedConfigSignal,
        _ walletContext: WalletContext
    ) {
        /* TODO: Wallet. Remove that?
        let presentationData = sharedContext.currentPresentationData.with({ $0 })
        let navigationController = NavigationController(
            mode: .single,
            theme: .init(presentationTheme: presentationData.theme),
            backgroundDetailsMode: nil
        )
        navigationController.setViewControllers([WalletApplicationSplashScreen(theme: presentationData.theme)], animated: false)
        presentOnMain(navigationController)
        */
        guard let navigationController = sharedContext.mainWindow?.viewController as? NavigationController else {
            return
        }
        let begin: () -> Void = { [weak self] in
            guard let strongSelf = self else { return }
            let presentationData = strongSelf.sharedContext.currentPresentationData.with({ $0 })

            navigationController.pushViewController(controller)
            
            var previousBlockchainName = initialResolvedConfig.networkName
            
            let disposable = (updatedConfigValue |> deliverOnMainQueue).start(next: { _, blockchainName, blockchainNetwork, config in
                let disposable = walletContext.tonInstance.validateConfig(config: config, blockchainName: blockchainName).start(completed: {
                    walletContext.tonInstance.updateConfig(config: config, blockchainName: blockchainName)
                    
                    if previousBlockchainName != blockchainName {
                        previousBlockchainName = blockchainName
                        
                        let overlayController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                        strongSelf.presentOnMain(overlayController)
                        
                        let disposable = (deleteAllLocalWalletsData(storage: walletContext.storage, tonInstance: walletContext.tonInstance)
                        |> deliverOnMainQueue).start(error: { [weak overlayController] _ in
                            overlayController?.dismiss()
                        }, completed: { [weak overlayController] in
                            // TODO: Wallet. Maybe we will show some kind of message here?
                            overlayController?.dismiss()
                            navigationController.popToRoot(animated: false)
                        })
                        strongSelf.walletDisposableSet.add(disposable)
                    }
                })
                strongSelf.walletDisposableSet.add(disposable)
            })
            strongSelf.walletDisposableSet.add(disposable)
        }
        if let splashScreen = navigationController.viewControllers.first as? WalletApplicationSplashScreen, let _ = controller as? WalletSplashScreen {
            splashScreen.animateOut(completion: {
                begin()
            })
        } else {
            begin()
        }
    }
    private func presentOnMain(_ controller: ContainableController) {
        sharedContext.mainWindow?.present(controller, on: .root)
    }
    // MARK: - Fork End
}

private func chatLocationContext(holder: Atomic<ChatLocationContextHolder?>, account: Account, data: ChatReplyThreadMessage) -> ReplyThreadHistoryContext {
    let holder = holder.modify { current in
        if let current = current as? ChatLocationContextHolderImpl {
            return current
        } else {
            return ChatLocationContextHolderImpl(account: account, data: data)
        }
    } as! ChatLocationContextHolderImpl
    return holder.context
}

private final class ChatLocationContextHolderImpl: ChatLocationContextHolder {
    let context: ReplyThreadHistoryContext
    
    init(account: Account, data: ChatReplyThreadMessage) {
        self.context = ReplyThreadHistoryContext(account: account, peerId: data.messageId.peerId, data: data)
    }
}

func getAppConfiguration(transaction: Transaction) -> AppConfiguration {
    let appConfiguration: AppConfiguration = transaction.getPreferencesEntry(key: PreferencesKeys.appConfiguration)?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
    return appConfiguration
}

func getAppConfiguration(postbox: Postbox) -> Signal<AppConfiguration, NoError> {
    return postbox.preferencesView(keys: [PreferencesKeys.appConfiguration])
    |> map { view -> AppConfiguration in
        let appConfiguration: AppConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        return appConfiguration
    }
    |> distinctUntilChanged
}
