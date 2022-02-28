import EasyDi
import ForkNetwork

final class NetworkAssembly: Assembly {
    
    // MARK: - Private properties
    
    private lazy var requestManagerAssembly: RequestManagerAssembly = context.assembly()
    
    // MARK: - Public properties
    
    var errorInterceptor: ErrorInterceptorInput & ErrorInterceptorOutput {
        return define(init: ErrorInterceptor())
    }
    
    var sendNetwork: SendNetwork {
        return define(
            scope: .lazySingleton,
            init: SendNetwork(
                requestManager: self.requestManagerAssembly.requestManager,
                errorInterceptor: self.errorInterceptor
            )
        )
    }
}
