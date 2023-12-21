import Foundation
import Configuration


/// A configuration data value.
///
/// Can be initialized from configuration values provided by a ``ConfigurationManager`` instance.
///
public protocol ConfigurationData {
    init(from configurationManager: ConfigurationManager) throws
}
