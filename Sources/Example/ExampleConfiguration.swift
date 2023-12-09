import ConfigurationReader
import Configuration


struct ExampleConfiguration {
    var a: String
    var b: Int
}


enum ParseError: Error {
    case failedToParseField(String)
}


extension ExampleConfiguration: ConfigurationData, Equatable {
    init(from configurationManager: ConfigurationManager) throws {
        guard let a = configurationManager["a"] as? String else {
            throw ParseError.failedToParseField("a")
        }
        guard let b = configurationManager["b"] as? Int else {
            throw ParseError.failedToParseField("b")
        }

        self.a = a
        self.b = b
    }
}
