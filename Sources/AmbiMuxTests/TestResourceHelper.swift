import Foundation

enum TestResourceError: Error {
    case resourceNotFound(resource: String, extension: String)
    case directoryCreationFailed(path: String, error: Error)
    case directoryRemovalFailed(path: String, error: Error)
}

struct TestResourceHelper {
    static func resourcePath(for resource: String, withExtension ext: String) throws -> String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: ext) else {
            throw TestResourceError.resourceNotFound(resource: resource, extension: ext)
        }
        return url.path
    }

    static func createTestDirectory() throws -> String {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let uuid = UUID().uuidString
        let testDirectory = temporaryDirectory.appendingPathComponent("AmbiMuxTests_\(uuid)")

        do {
            try fileManager.createDirectory(
                at: testDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw TestResourceError.directoryCreationFailed(
                path: testDirectory.path, error: error)
        }
        return testDirectory.path
    }

    static func removeTestDirectory(at path: String) throws {
        let fileManager = FileManager.default
        let testDirectory = URL(fileURLWithPath: path)

        if fileManager.fileExists(atPath: testDirectory.path) {
            do {
                try fileManager.removeItem(at: testDirectory)
            } catch {
                throw TestResourceError.directoryRemovalFailed(
                    path: testDirectory.path, error: error)
            }
        }
    }
}
