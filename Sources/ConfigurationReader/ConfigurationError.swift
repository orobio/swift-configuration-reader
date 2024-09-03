public enum ConfigurationError: Error {
    case fileTooLarge(fileName: String)
    case missingFile(fileName: String)
    case fileReadError(fileName: String, error: any Error)
    case configurationDataInitializationError(type: any ConfigurationData.Type, error: any Error)
    case unknownError(any Error)
}

extension ConfigurationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fileTooLarge(let fileName):
            "file too large: \(fileName)"

        case .missingFile(let fileName):
            "missing file: \(fileName)"

        case .fileReadError(let fileName, let error):
            "failed to read from \(fileName): \(error)"

        case .configurationDataInitializationError(let type, let error):
            "failed to initialize \(type): \(error)"

        case .unknownError(let error):
            "unknown error: \(error)"
        }
    }
}
