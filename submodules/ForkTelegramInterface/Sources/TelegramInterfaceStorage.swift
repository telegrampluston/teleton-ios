import AccountContext

public protocol TelegramInterfaceStorage {
    var interface: TelegramInterface? { get }
    func populateInterface(with accountContext: AccountContext)
}

final class TelegramInterfaceStorageImpl: TelegramInterfaceStorage {
        
    public var interface: TelegramInterface?
    
    public func populateInterface(with accountContext: AccountContext) {
        interface = TelegramInterfaceImpl(accountContext: accountContext)
    }
    
    init() { }
}
