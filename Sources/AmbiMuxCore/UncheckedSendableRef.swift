/// `@Sendable` クロージャで参照型をキャプチャしたい時の簡易ラッパー。
///
/// `Sendable` でない参照型をクロージャに渡す必要がある時に、呼び出し側がスレッド安全性を担保する前提で
/// `@unchecked Sendable` として包む用途を想定する。
final nonisolated class UncheckedSendableRef<T>: @unchecked Sendable {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

