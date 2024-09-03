import AsyncAlgorithms
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

    public var activeErrors = [any Error]()

    let logger: Logger

    private var _overrides = ConfigurationValues()
    private let _overridesTriggerStream: AsyncStream<Void>
    private let _overridesTriggerContinuation: AsyncStream<Void>.Continuation

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

        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        self._overridesTriggerStream = stream
        self._overridesTriggerContinuation = continuation
        self._overridesTriggerContinuation.yield()
    }


    /// Override configuration.
    ///
    /// Manipulate the configuration overrides, which can be used for overriding any
    /// configuration values from other sources.
    ///
    /// Parameter body: Closure for manipulating the overrides. The new overrides are
    ///                 applied when the closure ends.
    ///
    public func withOverrides(body: @Sendable (inout ConfigurationValues) -> Void) -> Void {
        body(&self._overrides)
        _overridesTriggerContinuation.yield()
    }


    /// Override a configuration value.
    ///
    /// Parameter path: Path of the configuration value.
    ///
    /// Parameter value: New value for the specified configuration path. Or nil to remove the override.
    ///
    public func setOverride(_ path: String, to value: (any Sendable)?) {
        withOverrides { overrides in
            overrides[path] = value
        }
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
                return nil // no error
            } catch {
                logger.error("Failed to initialize configuration data type: \(ConfigurationDataType.self), error: \(error)")
                return .configurationDataInitializationError(type: ConfigurationDataType.self, error: error)
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
            self.updateActiveErrors()
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
            self.currentRunLoopError = nil
            self.updateActiveErrors()
            finished = true
        }

        let filesStatesStream = try await configurationFilesStatesStream(
            for: self.filesSpecifications,
            debounceTime: self.debounceTime
        )

        let configStream = combineLatest(filesStatesStream, self._overridesTriggerStream)

        for await (fileSpecificationsWithStates, _) in configStream.cancelOnGracefulShutdown() {
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
                configurationManager.load(self._overrides.values)

                logger.debug("New configuration data available")
                self.configurationStreamHandlers.forEach { $0.process(configurationManager) }
                self.latestConfigurationManager = configurationManager
                self.currentRunLoopError = nil
            } catch {
                logger.error("Failed to get configuration data: \(error)")
                self.currentRunLoopError = error
            }

            self.updateActiveErrors()
        }
    }


    private func updateActiveErrors() {
        if let currentRunLoopError {
            self.activeErrors = [currentRunLoopError]
        } else {
            self.activeErrors = self.configurationStreamHandlers.compactMap(\.currentProcessError)
        }
    }


    private func removeConfigurationStreamHandler(withID id: ConfigurationStreamHandler.ID) {
        self.configurationStreamHandlers.removeAll { $0.id === id }
    }


    // Private data
    private class ConfigurationStreamHandler {
        final class ID: Sendable {}
        let id = ID()

        let doProcess: (ConfigurationManager) -> ConfigurationError?
        let finish: () -> ()
        var currentProcessError: Error?

        init(
            doProcess: @escaping (ConfigurationManager) -> ConfigurationError?,
            finish: @escaping () -> ()
        ) {
            self.doProcess = doProcess
            self.finish = finish
        }

        func process(_ configurationManager: ConfigurationManager) {
            self.currentProcessError = doProcess(configurationManager)
        }
    }

    private var configurationStreamHandlers = [ConfigurationStreamHandler]()
    private var latestConfigurationManager: ConfigurationManager?
    private var currentRunLoopError: Error?
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
            throw ConfigurationError.fileTooLarge(fileName: fileSpecification.path)

        case .noReadableFile:
            if fileSpecification.optional {
                return nil
            } else {
                throw ConfigurationError.missingFile(fileName: fileSpecification.path)
            }

        case .fileReadError(let error):
            throw ConfigurationError.fileReadError(fileName: fileSpecification.path, error: error)
        }
    }
}
