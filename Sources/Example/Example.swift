import ConfigurationReader
import ServiceLifecycle
import Logging


@main
struct Example {
    static func main() async throws {
        // Init logging
        LoggingSystem.bootstrap { label in
            var logHandler = StreamLogHandler.standardError(label: label)
            logHandler.logLevel = .trace
            return logHandler
        }
        let logger = Logger(label: "Example")

        // Create configuration service
        let configurationService = ConfigurationService(
            filesSpecifications: [
                // Configuration files should be in JSON format. Try modifying and deleting
                // the example files to see the behavior of the library.
                ConfigurationFileSpecification(path: "Sources/Example/test1.json", optional: false),
                ConfigurationFileSpecification(path: "Sources/Example/test2.json", optional: true),
            ],
            loadEnvironmentVariables: true,
            loadCommandLineArguments: true
        )

        // Create test service
        let testService = TestService(configurationService: configurationService)

        // Start service group
        let serviceGroup = ServiceGroup(
            configuration: .init(
                services: [
                    .init(service: configurationService),
                    .init(service: testService)
                ],
                gracefulShutdownSignals: [.sigterm, .sigint],
                cancellationSignals: [],
                logger: logger
            )
        )
        try await serviceGroup.run()
    }
}
