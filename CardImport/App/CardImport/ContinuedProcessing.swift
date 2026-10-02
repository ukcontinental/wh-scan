import Foundation
import BackgroundTasks

/// iOS 26+: lets a running batch continue after the user leaves the app, with system-provided progress UI.
/// Older iOS falls back to `beginBackgroundTask` (about 30 s) plus resume-on-launch.
@MainActor
final class ContinuedProcessing {
    static let shared = ContinuedProcessing()
    private var task: AnyObject?
    private var registered = false

    static var identifierPrefix: String { (Bundle.main.bundleIdentifier ?? "cardimport") + ".batch" }

    func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifierPrefix + ".*", using: nil) { task in
                guard let task = task as? BGContinuedProcessingTask else { return }
                Task { @MainActor in
                    ContinuedProcessing.shared.task = task
                    task.expirationHandler = {
                        // State is persisted after every step; the batch resumes on next launch.
                        task.setTaskCompleted(success: false)
                    }
                }
            }
        }
    }

    func begin(title: String, total: Int) {
        if #available(iOS 26.0, *) {
            let request = BGContinuedProcessingTaskRequest(identifier: Self.identifierPrefix + "." + UUID().uuidString,
                                                           title: title, subtitle: "0 / \(total)")
            request.strategy = .fail
            try? BGTaskScheduler.shared.submit(request)
        }
    }

    func update(done: Int, total: Int, subtitle: String) {
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.progress.totalUnitCount = Int64(max(total, 1))
            task.progress.completedUnitCount = Int64(done)
            task.updateTitle(task.title, subtitle: subtitle)
        }
    }

    func end(success: Bool) {
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.setTaskCompleted(success: success)
        }
        task = nil
    }
}
