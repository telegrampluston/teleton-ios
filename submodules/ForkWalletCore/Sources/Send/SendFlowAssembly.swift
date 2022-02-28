import Foundation
import AccountContext
import EasyDi

public final class SendFlowAssembly: Assembly {
    
    // MARK: - Private properties
    
    private lazy var networkAssembly: NetworkAssembly = context.assembly()
    
    // MARK: - Public methods
    
    public func sendFlow(
        with accountContext: AccountContext
    ) -> SendFlow {
        return define(
            scope: .lazySingleton,
            init: SendFlowImpl(
                with: accountContext,
                sendNetwork: self.networkAssembly.sendNetwork
            )
        )
    }
}
