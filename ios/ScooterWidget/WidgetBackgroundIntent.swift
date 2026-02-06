import AppIntents
import Foundation
import WidgetKit

@available(iOS 17, *)
public struct WidgetBackgroundIntent: AppIntent {
    static public var title: LocalizedStringResource = "Scooter Lock/Unlock"

    @Parameter(title: "Action")
    var action: String?

    public init() {}

    public init(action: String?) {
        self.action = action
    }

    public func perform() async throws -> some IntentResult {
        let prefs = UserDefaults(suiteName: "group.de.freal.unustasis")

        guard let action = action else {
            return .result()
        }

        // Set scanning state to true with timestamp
        prefs?.set(true, forKey: "scanning")
        prefs?.set(Date(), forKey: "scanningStartTime")
        prefs?.synchronize()

        // Request widget reload to show loading state immediately
        WidgetCenter.shared.reloadAllTimelines()

        // Execute the Bluetooth command
        let result = await withCheckedContinuation {
            (continuation: CheckedContinuation<(Bool, String?), Never>) in
            ScooterBluetoothManager.shared.executeCommand(action) { success, error in
                continuation.resume(returning: (success, error))
            }
        }

        // Update widget to remove scanning state
        prefs?.set(false, forKey: "scanning")
        prefs?.removeObject(forKey: "scanningStartTime")
        prefs?.synchronize()

        // Reload widget to show updated state
        WidgetCenter.shared.reloadAllTimelines()

        return .result()
    }

    // Run in background without opening the app
    static public var openAppWhenRun: Bool = false
}
