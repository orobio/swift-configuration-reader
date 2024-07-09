/// Combine latest values from multiple async sequences.
///
/// Takes an array of async sequences and creates an async sequence that
/// produces values of an Array with the latest values of all of the
/// base sequences.
///
/// The first array with latest values is produced as soon as all of the
/// base async sequences have produced at least one value.
///
/// - Parameter sequences: An array of sequences to combine.
///
/// - Returns: An async sequence that produces values of an array with all
///            latest values from the base sequences.
///
func combineLatest<S: AsyncSequence>(
    from sequences: [S],
    waitIndefinitelyWhenNoInputs: Bool = false
) -> AsyncStream<[S.Element]> where S: Sendable, S.Element: Sendable {
    return AsyncStream<[S.Element]> { continuation in
        if sequences.count == 0 {
            continuation.yield([])
            if waitIndefinitelyWhenNoInputs {
                // Keep continuation alive. May not be necessary, but just to be safe
                let task = Task {
                    await Task.sleepUntilCanceled()
                    withExtendedLifetime(continuation) {}
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            } else {
                continuation.finish()
            }
        } else {
            let storage = AsyncCombineLatestStorage<S.Element>(elementCount: sequences.count)
            let tasks = sequences.enumerated().map { index, sequence in
                Task {
                    for try await element in sequence {
                        await storage.update(index, with: element, yieldTo: continuation)
                    }
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                tasks.forEach { task in task.cancel() }
            }
        }
    }
}


private actor AsyncCombineLatestStorage<Element> {
    private var latest: [Element?]

    init(elementCount: Int) {
        self.latest = [Element?](repeating: nil, count: elementCount)
    }

    func update(_ index: Int, with element: Element, yieldTo continuation: AsyncStream<[Element]>.Continuation) {
        latest[index] = element
        let elements = latest.compactMap {$0}
        if elements.count == latest.count {
            continuation.yield(elements)
        }
    }
}

