import ServiceLifecycle
import AsyncAlgorithms


actor TestService: Service {
    let configurationService: ConfigurationService<ExampleConfiguration>

    init(configurationService: ConfigurationService<ExampleConfiguration>) {
        self.configurationService = configurationService
    }

    func run() async throws {
        print("Waiting for configuration")
        let configuration = try await configurationService.configuration
        print("Received configuration: \(configuration)")

        for await _ in AsyncTimerSequence(interval: .seconds(10), clock: .continuous).cancelOnGracefulShutdown() {
            print("Test loop")
        }

        print("Exiting test run loop")
    }
}
