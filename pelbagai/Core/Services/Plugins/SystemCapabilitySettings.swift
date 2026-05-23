import Foundation
import Combine

struct SystemCapabilityDescriptor: Identifiable, Equatable {
    var id: String { capabilityKey }
    let pluginID: String
    let pluginDisplayName: String
    let capabilityID: String
    let capabilityDisplayName: String
    let description: String
    let requiresUserApproval: Bool

    var capabilityKey: String {
        Self.key(pluginID: pluginID, capabilityID: capabilityID)
    }

    static func key(pluginID: String, capabilityID: String) -> String {
        "\(pluginID).\(capabilityID)"
    }
}

@MainActor
final class SystemCapabilitySettings: ObservableObject {
    static let shared = SystemCapabilitySettings()

    @Published private(set) var disabledCapabilityKeys: Set<String>

    private let userDefaults: UserDefaults
    private let disabledKey = "disabledSystemCapabilityKeys"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let stored = userDefaults.stringArray(forKey: disabledKey) ?? []
        self.disabledCapabilityKeys = Set(stored)
    }

    func isEnabled(pluginID: String, capabilityID: String) -> Bool {
        !disabledCapabilityKeys.contains(SystemCapabilityDescriptor.key(
            pluginID: pluginID,
            capabilityID: capabilityID
        ))
    }

    func setEnabled(_ enabled: Bool, pluginID: String, capabilityID: String) {
        let key = SystemCapabilityDescriptor.key(pluginID: pluginID, capabilityID: capabilityID)
        if enabled {
            disabledCapabilityKeys.remove(key)
        } else {
            disabledCapabilityKeys.insert(key)
        }
        persist()
    }

    private func persist() {
        userDefaults.set(disabledCapabilityKeys.sorted(), forKey: disabledKey)
    }
}
