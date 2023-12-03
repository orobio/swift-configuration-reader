import Inotify
@preconcurrency import SystemPackage
import Foundation


/// Watch a file for changes.
///
/// Creates an async sequence that produces ``FileState`` values for the specified file. If the file exists,
/// is readable, and not too large, a ``FileState/data`` value is produced with the contents of the file.
///
/// If the file exists and changes, a new state is produced immediately. If the file doesn't exist, the path
/// will be polled regularly to check for a newly created file. It can take upto the specified pol interval
/// before a new file is detected.
///
/// When the stream starts, the initial state of the file is produced immediately.
///
/// - Parameters:
///   - path: Path of the file to watch.
///   - maxFileSize: Maximum file size to read. If the file is larger, ``FileState/fileTooLarge`` is produced.
///   - polInterval: Pol interval to use when polling for a new file.
///   - inotifier: An instance of ``Inotifier``, which will be used for monitoring the file. If not provided,
///                a new instance will be created.
///
/// - Returns: Async sequence that produces the latest state of the watched file.
///
func watchFile(
    atPath path: String,
    maxFileSize: Int = 10 * 1024,
    polInterval: Duration = .seconds(5),
    inotifier: Inotifier? = nil
) async throws -> AsyncStream<FileState> {
    return AsyncStream { continuation in
        let task = Task {
            let fileManager = FileManager()
            let inotifier = try inotifier ?? Inotifier()

            var haveYieldedNoReadableFile = false
            while !Task.isCancelled {
                if fileManager.isReadableFile(atPath: path),
                    let inotifierEventStream = try? await inotifier.events(for: FilePath(path)) {
                    continuation.yield(readFile(atPath: path, maxFileSize: maxFileSize))
                    haveYieldedNoReadableFile = false
                    for await event in inotifierEventStream {
                        if event.flags.contains(.modified) {
                            continuation.yield(readFile(atPath: path, maxFileSize: maxFileSize))
                        }

                        if event.flags.contains(.selfDeleted) ||
                           event.flags.contains(.selfMoved) {
                            break
                        }
                    }
                } else {
                    if !haveYieldedNoReadableFile {
                        continuation.yield(.noReadableFile)
                        haveYieldedNoReadableFile = true
                        try await Task.sleep(for: .seconds(0.5)) // Quickly retry once in case the file was just deleted and recreated
                    } else {
                        try await Task.sleep(for: polInterval)
                    }
                }
            }

            continuation.finish()

            withExtendedLifetime(inotifier) {}
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
    }
}


private func readFile(atPath filePath: String, maxFileSize: Int) -> FileState {
    guard let fileHandle = FileHandle(forReadingAtPath: filePath) else {
        return .noReadableFile
    }

    do {
        guard let data = try fileHandle.read(upToCount: maxFileSize + 1) else {
            return .data(Data())
        }

        if data.count <= maxFileSize {
            return .data(data)
        } else {
            return .fileTooLarge
        }
    } catch {
        return .fileReadError(error)
    }
}
