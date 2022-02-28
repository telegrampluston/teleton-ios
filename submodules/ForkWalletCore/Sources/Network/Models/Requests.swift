import Foundation
import ForkNetwork

struct GetTonAddressRequestData: RequestData {
    let userId: Int64
    
    var parameters: Parameters {
        [
            "userId": userId
        ]
    }
}
