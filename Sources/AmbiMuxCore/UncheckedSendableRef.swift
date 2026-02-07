final nonisolated class UncheckedSendableRef<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

