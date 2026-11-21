import Darwin
import Foundation
import UsageCore

enum UsageCredentialReader {
    static func readSmallFile(_ location: URL) throws -> Data {
        let descriptor = open(location.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw UsageReadError.requestFailed }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let maximumSize = 65_536
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size <= maximumSize else {
            throw UsageReadError.invalidResponse
        }
        let data = try handle.read(upToCount: maximumSize + 1) ?? Data()
        guard data.count <= maximumSize else { throw UsageReadError.invalidResponse }
        return data
    }

    static func isBearerToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16_384 && value.utf8.allSatisfy { (33...126).contains($0) }
    }

}
