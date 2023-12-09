import ConfigurationReader
import ServiceLifecycle


/// Provide configuration and monitor changes
///
/// This service's run loop will read configuration from specified sources.
/// The configuration is provided via the ``configuration`` property.
/// When any of the sources change, resulting in a different configuration,
/// the run loop will exit.
///
actor ConfigurationService<ConfigurationDataType: ConfigurationData & Sendable & Equatable>: Service {
    enum ConfigurationServiceError: Error {
        case failedToGetConfiguration
    }

    private let filesSpecifications: [ConfigurationFileSpecification]
    private let loadEnvironmentVariables: Bool
    private let loadCommandLineArguments: Bool

    private var currentConfiguration: ConfigurationDataType?
    private var continuations = [CheckedContinuation<ConfigurationDataType, any Error>]()
    private var isFinished = false


    /// Initialize with configuration type and configuration sources
    init(for: ConfigurationDataType.Type,
         filesSpecifications: [ConfigurationFileSpecification],
         loadEnvironmentVariables: Bool,
         loadCommandLineArguments: Bool
    ) {
        self.filesSpecifications = filesSpecifications
        self.loadEnvironmentVariables = loadEnvironmentVariables
        self.loadCommandLineArguments = loadCommandLineArguments
    }


    /// Get configuration
    ///
    /// Possibly wait for valid configuration to be loaded.
    ///
    var configuration: ConfigurationDataType {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                if self.isFinished {
                    continuation.resume(throwing: ConfigurationServiceError.failedToGetConfiguration)
                } else if let currentConfiguration = self.currentConfiguration {
                    continuation.resume(returning: currentConfiguration)
                } else {
                    self.continuations.append(continuation)
                }
            }
        }
    }


    /// Set the configuration and resume all continuations with the configuration value
    private func setConfiguration(_ configuration: ConfigurationDataType) {
        precondition(self.currentConfiguration == nil)
        self.currentConfiguration = configuration
        self.continuations.forEach { continuation in continuation.resume(returning: configuration) }
        self.continuations = []
    }


    /// Fail all continuations by throwing 'failedToGetConfiguration'
    private func failAllContinuations() {
        self.continuations.forEach { continuation in continuation.resume(throwing: ConfigurationServiceError.failedToGetConfiguration) }
        self.continuations = []
    }


    /// Service run loop
    func run() async throws {
        // Only run once
        precondition(self.isFinished == false)

        // When the run loop exits, indicate that we're finished, so no more
        // continuations will be added. Then fail all existing continuations.
        defer {
            self.isFinished = true
            failAllContinuations()
        }

        let configurationStream = try await ConfigurationDataType.stream(
            from: self.filesSpecifications,
            loadEnvironmentVariables: self.loadEnvironmentVariables,
            loadCommandLineArguments: self.loadCommandLineArguments
        )
        for await configuration in configurationStream.cancelOnGracefulShutdown() {
            if let currentConfiguration = self.currentConfiguration {
                // Valid configuration already set
                do {
                    let newConfiguration = try configuration.get()
                    if newConfiguration == currentConfiguration {
                        print("note: Ignoring new configuration, which is equal to previous configuration")
                    } else {
                        print("note: Changed configuration detected, shutting down")
                        break
                    }
                } catch {
                    print("error: Ignoring changed configuration due to an error: \(error)")
                }
            } else {
                // No configuration yet
                do {
                    let newConfiguration = try configuration.get()
                    print("note: Valid configuration found")
                    setConfiguration(newConfiguration)
                } catch {
                    print("error: Unable to get valid configuration: \(error)")
                }
            }
        }
    }

    deinit {
        // Fail any continuations that may still exist. Should only happen when the run loop is never executed.
        let continuations = self.continuations
        Task { [continuations] in
            continuations.forEach { continuation in continuation.resume(throwing: ConfigurationServiceError.failedToGetConfiguration) }
        }
    }
}
