extension Task where Success == Never, Failure == Never {
    static func sleepUntilCanceled() async {
        do {
            while true {
                try await Task.sleep(for: .seconds(3600))
            }
        } catch {}
    }
}
