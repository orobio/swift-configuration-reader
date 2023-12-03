public enum ConfigurationError: Error {
    case fileTooLarge(String)
    case missingFile(String)
    case fileReadError(String, any Error)
    case failedToParseConfiguration(any Error)
    case unknownError(any Error)
}
