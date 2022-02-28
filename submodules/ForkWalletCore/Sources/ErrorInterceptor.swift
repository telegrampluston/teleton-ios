import SwiftSignalKit

protocol ErrorInterceptorInput {
    /// Process the error. If returns true – then error is intercepted (showstopper) and we should stop our response processing.
    func process(_ error: WalletError) -> Bool
}

protocol ErrorInterceptorOutput {
    var updateIsRequiredSignal: Signal<Void, NoError> { get }
}

final class ErrorInterceptor: ErrorInterceptorInput, ErrorInterceptorOutput {
    
    // MARK: - Private properties
    
    private let updateIsRequiredValuePipe = ValuePipe<Void>()

    // MARK: - Public properties
    
    var updateIsRequiredSignal: Signal<Void, NoError> {
        updateIsRequiredValuePipe.signal()
    }
    
    // MARK: - Public methods
    func process(_ error: WalletError) -> Bool {
        return false
    }
}
