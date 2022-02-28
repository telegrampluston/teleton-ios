import EasyDi

final public class FileManagerAssembly: Assembly {
    public var fileManager: FileManager {
        return define(scope: .lazySingleton, init: FileManager(fileManager: .default))
    }
}
