import Configuration
import ServiceLifecycle
import Logging
import Foundation


/// Provide configuration values.
///
/// Allows the creation of multiple async sequences that produce specific ``ConfigurationData``
/// conforming values. Every async sequence produces its first value as soon as possible, which
/// is either immediately, or as soon as the service's run loop is started.
///
/// The configuration values are read from the input sources that are provided when the service
/// is created. When any of the configuration input files is changed, new values are produced.
///
public actor ConfigurationService: Service {
    // Configuration sources
    let filesSpecifications: [ConfigurationFileSpecification]
    let loadEnvironmentVariables: Bool
    let loadCommandLineArguments: Bool
    let debounceTime: Duration

    let logger: Logger

    /// Initialize with configuration type and configuration sources.
    ///
    ///   - filesSpecifications: The configuration files to load.
    ///   - loadEnvironmentVariables: Selects whether configuration from environment variables is loaded.
    ///   - loadCommandLineArguments: Selects whether configuration from command line arguments is loaded.
    ///
    public init(
        filesSpecifications: [ConfigurationFileSpecification],
        loadEnvironmentVariables: Bool,
        loadCommandLineArguments: Bool,
        logger: Logger = Logger(label: "ConfigurationService"),
        debounceTime: Duration = .milliseconds(100)
    ) {
        self.filesSpecifications = filesSpecifications
        self.loadEnvironmentVariables = loadEnvironmentVariables
        self.loadCommandLineArguments = loadCommandLineArguments
        self.logger = logger
        self.debounceTime = debounceTime
    }


    /// Create an async sequence, producing values of a ``ConfigurationData`` conforming type.
    ///
    /// Parameter type: Type of configuration values to produce.
    ///
    /// Returns: Async sequence of the provided type.
    ///
    public func stream<ConfigurationDataType>(_ type: ConfigurationDataType.Type) -> AnyAsyncSequence<ConfigurationDataType>
        where ConfigurationDataType: ConfigurationData & Equatable & Sendable {
        let (stream, continuation) = AsyncStream.makeStream(of: ConfigurationDataType.self)
        let configurationStreamHandler = ConfigurationStreamHandler { [logger] configurationManager in
            do {
                let configurationData = try ConfigurationDataType(from: configurationManager)
                logger.debug("Created configuration data value of type: \(ConfigurationDataType.self)")
                continuation.yield(configurationData)
            } catch {
                logger.error("Failed to parse configuration data for type: \(ConfigurationDataType.self), error: \(error)")
            }
        } finish: {
            continuation.finish()
        }

        // Store handler and handle termination
        self.configurationStreamHandlers.append(configurationStreamHandler)
        continuation.onTermination = { @Sendable [id = configurationStreamHandler.id] _ in
            Task { await self.removeConfigurationStreamHandler(withID: id) }
        }

        // Immediately process current value, if available
        if let configurationManager = self.latestConfigurationManager {
            configurationStreamHandler.process(configurationManager)
        }

        // Immediately finish stream if the service is finished
        if self.finished {
            configurationStreamHandler.finish()
        }

        return AnyAsyncSequence(stream.removeDuplicates())
    }


    /// Service run loop.
    ///
    /// Monitors the configuration inputs and produces values for the async sequences
    /// with configuration data.
    ///
    /// Must be run exactly once.
    ///
    public func run() async throws {
        precondition(finished == false)
        defer {
            self.configurationStreamHandlers.forEach { $0.finish() }
            finished = true
        }

        let filesStatesStream = try await configurationFilesStatesStream(
            for: self.filesSpecifications,
            debounceTime: self.debounceTime
        )
        for await fileSpecificationsWithStates in filesStatesStream.cancelOnGracefulShutdown() {
            do {
                let datas = try datasFromConfigurationFilesStates(fileSpecificationsWithStates)

                // Create a new ConfigurationManager and read the configuration from all sources
                let configurationManager = ConfigurationManager()
                datas.forEach { configurationManager.load(data: $0) }
                if self.loadEnvironmentVariables {
                    configurationManager.load(.environmentVariables)
                }
                if self.loadCommandLineArguments {
                    configurationManager.load(.commandLineArguments)
                }

                logger.debug("New configuration data available")
                self.configurationStreamHandlers.forEach { $0.process(configurationManager) }
                self.latestConfigurationManager = configurationManager
            } catch {
                logger.error("Failed to get configuration data: \(error)")
            }
        }
    }


    private func removeConfigurationStreamHandler(withID id: ConfigurationStreamHandler.ID) {
        self.configurationStreamHandlers.removeAll { $0.id === id }
    }


    // Private data
    private struct ConfigurationStreamHandler {
        final class ID: Sendable {}
        let id = ID()

        let process: (ConfigurationManager) -> ()
        let finish: () -> ()
    }

    private var configurationStreamHandlers = [ConfigurationStreamHandler]()
    private var latestConfigurationManager: ConfigurationManager?
    private var finished = false
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
private func datasFromConfigurationFilesStates(
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
