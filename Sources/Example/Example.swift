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
                ConfigurationFileSpecification(path: "./test1", optional: false),
                ConfigurationFileSpecification(path: "./test2", optional: true),
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
