import Foundation
import Configuration


/// A configuration data value.
///
/// Can be initialized from configuration values provided by a ``ConfigurationManager`` instance.
///
public protocol ConfigurationData {
    init(from configurationManager: ConfigurationManager) throws
}


extension ConfigurationData {
    /// Create an async sequence producing values of Self based on various configuration sources.
    ///
    /// Loads all configuration data from specified sources and initializes a value of Self from it.
    /// Whenever a configuration file changes, a new value is produced based on the new data.
    ///
    /// When configuration values are loaded from a specific source, they can override values from
    /// sources that are loaded earlier. The sources are loaded in the following order:
    /// - The configuration files, in the order they appear in the array.
    /// - Environment variables.
    /// - Command line arguments.
    ///
    /// - Parameters:
    ///   - filesSpecifications: The configuration files to load.
    ///   - loadEnvironmentVariables: Selects whether configuration from environment variables is loaded.
    ///   - loadCommandLineArguments: Selects whether configuration from command line arguments is loaded.
    ///
    /// - Returns: An async sequence producing values of Self instantiated from the latest configuration
    ///            data, or ``ConfigurationError``.
    ///
    public static func stream(
        from filesSpecifications: [ConfigurationFileSpecification],
        loadEnvironmentVariables: Bool,
        loadCommandLineArguments: Bool
    ) async throws -> AnyAsyncSequence<Result<Self, ConfigurationError>> {
        AnyAsyncSequence(
            try await configurationFilesStatesStream(for: filesSpecifications).map { fileSpecificationsWithStates in
                do {
                    let datas = try datasFromConfigurationFilesStates(fileSpecificationsWithStates)
                    let configurationManager = ConfigurationManager()
                    datas.forEach { configurationManager.load(data: $0) }
                    if loadEnvironmentVariables {
                        configurationManager.load(.environmentVariables)
                    }
                    if loadCommandLineArguments {
                        configurationManager.load(.commandLineArguments)
                    }
                    return .success(try Self.create(from: configurationManager))
                } catch let error as ConfigurationError {
                    return .failure(error)
                } catch {
                    return .failure(.unknownError(error))
                }
            }
        )
    }

    /// Helper function for instantiating Self
    ///
    /// Wraps any error thrown from Self.init into ConfigurationError.failedToParseConfigurationvalue.
    ///
    private static func create(from configurationManager: ConfigurationManager) throws -> Self {
        do {
            return try Self(from: configurationManager)
        } catch {
            throw ConfigurationError.failedToParseConfiguration(error)
        }
    }
}


/// Map an array of configuration file specifications with file states to an array of data.
///
/// If any of the configuration file states has an error, an error is thrown.
/// If any configuration file is missing and it is not optional, an error is thrown.
///
/// - Parameter fileSpecificationsWithStates: All file specifications and their corresponding state.
///
/// - Returns: All data instances with the contents of the configuration files.
///
func datasFromConfigurationFilesStates(
    _ fileSpecificationsWithStates: [(ConfigurationFileSpecification, FileState)]
) throws -> [Data] {
    return try fileSpecificationsWithStates.compactMap { (fileSpecification, state) in
        switch state {
        case .data(let data):
            return data

        case .fileTooLarge:
            throw ConfigurationError.fileTooLarge(fileSpecification.path)

        case .noReadableFile:
            if fileSpecification.optional {
                return nil
            } else {
                throw ConfigurationError.missingFile(fileSpecification.path)
            }

        case .fileReadError(let error):
            throw ConfigurationError.fileReadError(fileSpecification.path, error)
        }
    }
}
