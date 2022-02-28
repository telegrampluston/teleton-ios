import Foundation
import EasyDi
import ForkTelegramInterface

final public class RequestManagerAssembly: Assembly {
    
    private lazy var fileManagerAssembly: FileManagerAssembly = context.assembly()
    private lazy var telegramInterfaceStorageAssembly: TelegramInterfaceStorageAssembly = context.assembly()

    public var requestManager: RequestManager {
        return define(
            scope: .lazySingleton,
            init: RequestManager(
                fileManager: self.fileManagerAssembly.fileManager,
                decoder: self.jsonDecoder,
                lock: self.nsLock,
                deviceInfo: self.deviceInfo,
                urlSessionConfig: self.urlSessionConfiguration,
                telegramInterfaceStorage: self.telegramInterfaceStorageAssembly.interfaceStorage
            )
        )
    }
    
    private var jsonDecoder: JSONDecoder {
        JSONDecoder()
    }
    
    private var nsLock: NSLock {
        NSLock()
    }
    
    private var deviceInfo: DeviceInfo {
        DeviceInfo()
    }
    
    private var urlSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        return config
    }
    
}
