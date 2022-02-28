import Foundation
import SwiftSignalKit
import ForkNetwork

final class SendNetwork: BaseNetwork {
    
    /// Nested types
    private enum Methods: String {
        case wallet
    }
    
    // MARK: - Public methods
    
    func getAddress(userId: Int64) -> Signal<WalletResponse<WalletTonAddressResponse>, WalletError> {
        let url = URL(string: "\(API.apiUrl)\(Methods.wallet.rawValue)/\(userId)")!
        let signal = (requestManager.request(
            withMethod: .get,
            url: url
        ) as Signal<WalletResponse<WalletTonAddressResponse>, Error>)
        |> mapError { WalletError(error: $0) }
        |> mapToSignal { [weak self] response -> Signal<WalletResponse<WalletTonAddressResponse>, WalletError> in
            guard let strongSelf = self else {
                return .complete()
            }
            return strongSelf.parseWalletResponse(response)
        }
        return signal
    }
}
