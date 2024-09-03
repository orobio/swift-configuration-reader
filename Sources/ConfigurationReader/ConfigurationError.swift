public enum ConfigurationError: Error {
    case fileTooLarge(fileName: String)
    case missingFile(fileName: String)
    case fileReadError(fileName: String, error: any Error)
    case configurationDataInitializationError(type: any ConfigurationData.Type, error: any Error)
    case unknownError(any Error)
}
