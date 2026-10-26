import Foundation

/// A scheduled piece of work that can be cancelled.
protocol Cancellable: AnyObject {
    func cancel()
}

/// Runs work later on the main thread. Abstracted so tests can drive time manually.
protocol Scheduling: AnyObject {
    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellable
}

final class MainQueueScheduler: Scheduling {
    private final class Item: Cancellable {
        let workItem: DispatchWorkItem
        init(_ workItem: DispatchWorkItem) { self.workItem = workItem }
        func cancel() { workItem.cancel() }
    }

    @discardableResult
    func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: item)
        return Item(item)
    }
}

/// Runs `work` on the main thread: right away when already there, otherwise asynchronously.
func performOnMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread {
        work()
    } else {
        DispatchQueue.main.async(execute: work)
    }
}
