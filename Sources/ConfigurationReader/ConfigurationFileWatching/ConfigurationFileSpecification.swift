/// Specification of a file for reading configuration from.
///
/// If optional equals true, there will be no error generated if the
/// file does not exist.
///
public struct ConfigurationFileSpecification: Sendable {
    public var path: String
    public var optional: Bool

    public init(path: String, optional: Bool) {
        self.path = path
        self.optional = optional
    }
}
