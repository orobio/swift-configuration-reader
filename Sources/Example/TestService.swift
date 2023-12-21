import ServiceLifecycle
import AsyncAlgorithms
import ConfigurationReader

/// Simple test service that depends on the configuration service
///
actor TestService: Service {
    let configurationService: ConfigurationService

    /// Initialize with configuration service
    ///
    init(configurationService: ConfigurationService) {
        self.configurationService = configurationService
    }

    /// Service run loop: wait for configuration updates
    ///
    func run() async throws {
        print("Starting test service run loop")

        for await configuration in await configurationService.stream(ExampleConfiguration.self).cancelOnGracefulShutdown() {
            print("Test service received new configuration: \(configuration)")
        }

        print("Exiting test service run loop")
    }
}
