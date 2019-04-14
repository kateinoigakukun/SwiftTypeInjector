import Foundation

public struct SwiftcInvocator {
    private static func getSearchPaths() -> [URL] {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pathEnvVar = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let paths = pathEnvVar.split(separator: ":").map(String.init).map {
            (path: String) -> URL in
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            } else {
                return cwd.appendingPathComponent(path)
            }
        }
        return paths
    }

    private static func lookupExecutablePath(filename: String) -> URL? {
        let paths = getSearchPaths()
        for path in paths {
            let url = path.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public static func locateSwiftc() -> URL? {
        return lookupExecutablePath(filename: "swiftc")
    }

    private static let _swiftcURL: URL? = SwiftcInvocator.locateSwiftc()
    private let swiftcURL: URL
    private let sourceFile: URL

    enum Error: Swift.Error {
        case couldNotFindSwiftc
        case couldNotParseOutputData
    }

    init(sourceFile: URL, swiftcURL: URL? = nil) throws {
        guard let swiftcURL = swiftcURL ?? SwiftcInvocator._swiftcURL else {
            throw Error.couldNotFindSwiftc
        }
        self.swiftcURL = swiftcURL
        self.sourceFile = sourceFile
    }

    func dumpAST() throws -> String {
        return try invoke(arguments: ["-frontend", "-dump-ast", sourceFile.path])
    }

    func invoke(arguments: [String]) throws -> String {

        let stdoutPipe = Pipe()
        var stdoutData = Data()
        let stdoutSource = DispatchSource.makeReadSource(
            fileDescriptor: stdoutPipe.fileHandleForReading.fileDescriptor)
        stdoutSource.setEventHandler {
            stdoutData.append(stdoutPipe.fileHandleForReading.availableData)
        }
        stdoutSource.resume()

        let process = Process()
        process.launchPath = swiftcURL.path
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.launch()
        process.waitUntilExit()
        guard let result = String(data: stdoutData, encoding: .utf8) else {
            throw Error.couldNotParseOutputData
        }
        return result
    }
}
