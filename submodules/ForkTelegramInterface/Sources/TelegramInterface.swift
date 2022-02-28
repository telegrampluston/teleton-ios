import Foundation
import AccountContext
import TelegramPresentationData
import SwiftSignalKit

public protocol TelegramInterface {
    var localeString: String { get }
    var locale: Locale { get }
    var updatedPresentationDataSignal: Signal<Void, NoError> { get }
}

final class TelegramInterfaceImpl: TelegramInterface {
    
    // MARK: - Private properties
    
    private let accountContext: AccountContext
    private var currentPresentationData: PresentationData
    private let updatedPresentationDataValuePipe = ValuePipe<Void>()

    private var presentationDataDisposable: Disposable?
        
    // MARK: - Public methods
    
    public var updatedPresentationDataSignal: Signal<Void, NoError> {
        updatedPresentationDataValuePipe.signal()
    }
    
    public var localeString: String {
        currentPresentationData.strings.baseLanguageCode
    }
    
    public var locale: Locale {
        Locale(identifier: localeString)
    }
    
    // MARK: - Lifecycle
    
    init(accountContext: AccountContext) {
        self.accountContext = accountContext
        self.currentPresentationData = accountContext.sharedContext.currentPresentationData.with { $0 }
        subscribeToPresentationData()
    }
    
    deinit {
        presentationDataDisposable?.dispose()
    }
    
    // MARK: - Private methods
    
    private func subscribeToPresentationData() {
        presentationDataDisposable = (accountContext.sharedContext.presentationData
            |> filter { [weak self] in
                return self?.currentPresentationData !== $0
            })
            .start { [weak self] in
                self?.currentPresentationData = $0
                self?.updatedPresentationDataValuePipe.putNext(())
            }
    }
}
