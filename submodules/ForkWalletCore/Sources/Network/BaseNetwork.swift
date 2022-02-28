import Foundation
import SwiftSignalKit
import ForkNetwork

class BaseNetwork {
    
    // MARK: - Private properties
    
    let requestManager: RequestManager
    let errorInterceptor: ErrorInterceptorInput
    
    // MARK: - Lifecycle
    
    init(requestManager: RequestManager, errorInterceptor: ErrorInterceptorInput) {
        self.requestManager = requestManager
        self.errorInterceptor = errorInterceptor
    }
    
    // MARK: - Public methods
    
    func parseWalletResponse<T: Decodable>(
        _ response: WalletResponse<T>
    ) -> Signal<WalletResponse<T>, WalletError> {
        return Signal { [weak self] subscriber in
            if response.status != .ok {
                let error = WalletError(message: response.message, code: response.code)
                if (self?.errorInterceptor.process(error) ?? false) == false { // If interceptor haven't intercepted our error
                    subscriber.putError(error)
                }
            } else {
                subscriber.putNext(response)
            }
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
