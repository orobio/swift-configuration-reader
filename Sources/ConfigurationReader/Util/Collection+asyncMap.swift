extension Collection {
    /// Map with async closure.
    ///
    public func map<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        let n = self.count
        if n == 0 {
            return []
        }

        var result = ContiguousArray<T>()
        result.reserveCapacity(n)

        var i = self.startIndex

        for _ in 0..<n {
            result.append(try await transform(self[i]))
            formIndex(after: &i)
        }

        return Array(result)
    }
}
