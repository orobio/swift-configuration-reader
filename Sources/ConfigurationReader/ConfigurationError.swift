public enum ConfigurationError: Error {
    case fileTooLarge(String)
    case missingFile(String)
    case fileReadError(String, any Error)
    case configurationDataInitializationError(type: any ConfigurationData.Type, error: any Error)
    case unknownError(any Error)
}
