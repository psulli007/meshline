//
// ContactLabelStore.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import Foundation

/// Local, on-device names the user gives to people ("Mom", "Alex from work").
/// Keyed by the person's key fingerprint when known (stable across sessions),
/// otherwise by their mesh ID. Never sent over the network.
final class ContactLabelStore: ObservableObject {
    static let shared = ContactLabelStore()
    static let defaultsKey = "meshline.contactLabels"
    static let maxLabelLength = 60

    @Published private(set) var labels: [String: String]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.labels = (defaults.dictionary(forKey: Self.defaultsKey) as? [String: String]) ?? [:]
    }

    func label(for key: String) -> String? {
        labels[key]
    }

    /// Saves a trimmed label; an empty label removes it.
    func setLabel(_ label: String?, for key: String) {
        let trimmed = Self.clean(label)
        if let trimmed {
            labels[key] = trimmed
        } else {
            labels[key] = nil
        }
        defaults.set(labels, forKey: Self.defaultsKey)
    }

    /// Clears every label (used by panic wipe).
    func removeAll() {
        labels = [:]
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    static func clean(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxLabelLength))
    }
}
