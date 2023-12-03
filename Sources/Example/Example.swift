import ConfigurationReader


@main
struct Example {
    static func main() async throws {
        let exampleConfigurationStream = try await ExampleConfiguration.stream(
            from: [
                ConfigurationFileSpecification(path: "./test1", optional: false),
                ConfigurationFileSpecification(path: "./test2", optional: true),
            ],
            loadEnvironmentVariables: true,
            loadCommandLineArguments: true
        )

        for await exampleConfiguration in exampleConfigurationStream {
            do {
                let exampleConfiguration = try exampleConfiguration.get()
                print(exampleConfiguration)
            } catch {
                print("error: \(error)")
            }
        }
    }
}
