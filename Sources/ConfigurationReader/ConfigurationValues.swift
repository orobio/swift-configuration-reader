/// Configuration values
///
/// Wraps a dictionary of [String: Any] that can be used as configuration
/// input. A subscript is provided to be able to get/set values based
/// on a path, where a colon ':' is used as component separator.
/// For example: configurationValues["root:section:key"] = value
///
public struct ConfigurationValues: @unchecked Sendable {
    // *********************************************
    // This struct is @unchecked Sendable. We must
    // take care to only store sendable values!
    // *********************************************
    public private(set) var values = [String: Any]()

    /// Subscript
    ///
    /// Can be used to set a configuration value, or remove it (nil).
    ///
    public subscript(_ path: String) -> (any Sendable)? {
        get {
            fatalError("unimplemented getter for configuration value")
            // TODO: return values.getValue(at: path)
            //       and find a way to cast from Any? to (any Sendable)?
        }

        set {
            values.setValue(at: path, to: newValue)
        }
    }
}

private extension Dictionary<String, Any> {
    mutating func setValue(
        at pathComponents: ArraySlice<Substring>,
        to value: Any?
    ) {
        guard let nextPathComponent = pathComponents.first.map(String.init) else {
            self[""] = value
            return
        }

        if pathComponents.count == 1 {
            self[nextPathComponent] = value
        } else {
            var dictionary = (self[nextPathComponent] as? Dictionary<String, Any>) ?? [:]
            dictionary.setValue(at: pathComponents.dropFirst(), to: value)
            self[nextPathComponent] = dictionary
        }
    }

    mutating func setValue(
        at path: String,
        to value: Any?
    ) {
        let pathComponents = path.split(separator: ":")
        self.setValue(at: pathComponents[...], to: value)
    }

    func getValue(
        at pathComponents: ArraySlice<Substring>
    ) -> Any? {
        guard let nextPathComponent = pathComponents.first.map(String.init) else {
            return self[""]
        }

        if pathComponents.count == 1 {
            return self[nextPathComponent]
        } else {
            if let dictionary = self[nextPathComponent] as? Dictionary<String, Any> {
                return dictionary.getValue(at: pathComponents.dropFirst())
            } else {
                return nil
            }
        }
    }

    func getValue(
        at path: String
    ) -> Any? {
        let pathComponents = path.split(separator: ":")
        return self.getValue(at: pathComponents[...])
    }
}
