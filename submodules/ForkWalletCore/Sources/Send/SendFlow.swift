import Foundation
import SwiftSignalKit
import AccountContext
import Display
import PresentationDataUtils
import Postbox

public protocol SendFlow {
    /// Send TON to specific user
    func send(to peerId: PeerId)
}

final class SendFlowImpl: SendFlow {
    
    // MARK: - Private properties
    
    private let accountContext: AccountContext
    private let sendNetwork: SendNetwork
    private var disposableSet = DisposableSet()
    
    // MARK: - Lifecycle
    
    init(
        with accountContext: AccountContext,
        sendNetwork: SendNetwork
    ) {
        self.accountContext = accountContext
        self.sendNetwork = sendNetwork
    }
    
    deinit {
        disposableSet.dispose()
    }
    
    // MARK: - Public methods
    
    func send(to peerId: PeerId) {
        let presentationData = accountContext.sharedContext.currentPresentationData.with({ $0 })
        let disposable = (
            sendNetwork.getAddress(userId: peerId.id._internalGetInt64Value()) |> map { $0.payload.wallet } |> deliverOnMainQueue
        ).start(next: { [weak self] address in
            guard let strongSelf = self else {
                return
            }
            strongSelf.accountContext.sharedContext.openWallet(
                context: strongSelf.accountContext,
                walletContext: .send(address: address, amount: nil, comment: nil),
                present: { [weak self] controller in
                    self?.presentOnMain(controller, push: true)
                }
            )
        }, error: { [weak self] error in
            guard let strongSelf = self else {
                return
            }
            let controller = textAlertController(
                context: strongSelf.accountContext,
                title: presentationData.strings.Wallet_Send_UserWalletNotLinkedTitle,
                text: presentationData.strings.Wallet_Send_UserWalletNotLinkedText,
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_OK, action: { }),
                ]
            )
            strongSelf.presentOnMain(controller)
        })
        disposableSet.add(disposable)
    }
    
    // MARK: - Private methods
    
    private func presentOnMain(_ controller: ViewController, push: Bool = false) {
        if push {
            (accountContext.sharedContext.mainWindow?.viewController as? NavigationController)?.pushViewController(controller)
        } else {
            accountContext.sharedContext.mainWindow?.present(controller, on: .root)
        }
    }
}
