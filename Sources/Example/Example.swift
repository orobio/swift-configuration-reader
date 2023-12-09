import ConfigurationReader
import ServiceLifecycle
import Logging


@main
struct Example {
    static func main() async throws {
        let logger = Logger(label: "example.logger.com")

        let configurationService = ConfigurationService(
            for: ExampleConfiguration.self,
            filesSpecifications: [
                ConfigurationFileSpecification(path: "./test1", optional: false),
                ConfigurationFileSpecification(path: "./test2", optional: true),
            ],
            loadEnvironmentVariables: true,
            loadCommandLineArguments: true
        )

        let testService = TestService(configurationService: configurationService)

        let serviceGroup = ServiceGroup(
            configuration: .init(
                services: [
                    .init(service: configurationService, successTerminationBehavior: .gracefullyShutdownGroup),
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
