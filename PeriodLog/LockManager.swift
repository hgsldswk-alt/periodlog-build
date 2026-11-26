import SwiftUI
import LocalAuthentication

@MainActor final class LockManager: ObservableObject {
    @Published var locked = false
    @Published var covered = false
    @Published var authenticating = false
    @Published var failure = false
    private var wentToBackground = false
    func transition(_ phase: ScenePhase, enabled: Bool) {
        guard enabled else { locked = false; covered = false; return }
        switch phase {
        case .background: covered = true; locked = true; wentToBackground = true
        case .inactive: covered = true
        case .active:
            if !authenticating { covered = false }
            if wentToBackground || locked { locked = true; Task { await unlock() } }
        @unknown default: break
        }
    }
    func unlock() async {
        guard !authenticating else { return }
        authenticating = true; failure = false
        defer { authenticating = false; covered = false }
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { failure = true; return }
        do {
            let result = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: L.t("解锁你的本地经期记录"))
            locked = !result; wentToBackground = !result
        } catch { failure = true }
    }
}
