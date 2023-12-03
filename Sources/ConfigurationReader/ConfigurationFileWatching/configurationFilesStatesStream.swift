import Inotify
import Foundation
import AsyncAlgorithms


/// Create an async sequence that produces the specifications and states of multiple configuration files.
///
/// Takes an array of configuration file specifications and creates an async sequence that produces values
/// of an array with all file specifications combined with the latest state of the corresponding file.
///
/// - Parameter fileSpecifications: Specifications for all configuration files to watch.
///
/// - Returns: Async sequence producing values of an array with configuration file specifications combined
///            with their corresponding file state.
///
func configurationFilesStatesStream(
    for fileSpecifications: [ConfigurationFileSpecification]
) async throws -> AsyncStream<[(ConfigurationFileSpecification, FileState)]> {
    let inotifier = try Inotifier()
    let fileSpecificationsWithStates = try await fileSpecifications.map { fileSpecification in
        try await watchFile(atPath: fileSpecification.path, inotifier: inotifier)
        .debounce(for: .seconds(1)) // Ignore multiple changes in a short time, like deleting and recreating the file.
        .removeDuplicates()
        .map { fileState in
            (fileSpecification, fileState)
        }
    }
    return combineLatest(from: fileSpecificationsWithStates)
}
