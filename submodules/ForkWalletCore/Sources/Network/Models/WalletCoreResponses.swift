import Foundation

enum WalletResponseStatus: String, Decodable {
    case ok
    case error
}

struct WalletResponse <T: Decodable>: Decodable {
    let code: WalletErrorCode?
    let status: WalletResponseStatus
    let message: String
    let payload: T
    
    enum CodingKeys: CodingKey {
        case code, status, message, payload
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.payload = try container.decode(T.self)
        self.code = nil
        self.message = ""
        self.status = .ok
    }
}

typealias EmptyPayloadWalletResponse = WalletResponse<[String: String]> // If we don't care about payload

struct WalletTonAddressResponse: Decodable {
    let wallet: String
}
