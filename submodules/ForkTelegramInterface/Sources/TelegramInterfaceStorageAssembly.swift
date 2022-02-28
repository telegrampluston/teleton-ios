import Foundation
import EasyDi

public class TelegramInterfaceStorageAssembly: Assembly {

    public var interfaceStorage: TelegramInterfaceStorage {
        return define(
            scope: .lazySingleton,
            init: TelegramInterfaceStorageImpl()
        )
    }
}
