//
// MeshlineSafety.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//
// Disaster features that need no server: "I'm safe" check-ins, the invite
// text and nudge, and the nearby counter. Check-ins are sent as ordinary
// private and group messages, so they get the same end-to-end encryption,
// sender authentication, mesh relay, 72 hour carry-forward and Nostr
// fallback as any other message. Nothing is sent to us.
//

import Foundation

enum SafetyStatus: String, CaseIterable, Identifiable {
    case safe
    case needHelp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .safe: return "I'm safe"
        case .needHelp: return "I need help"
        }
    }
}

struct CheckInLocation: Equatable {
    let latitude: Double
    let longitude: Double
}

enum SafetyCheckIn {
    static let maxNoteLength = 140

    /// The text sent to each person and group.
    static func message(
        status: SafetyStatus,
        note: String? = nil,
        location: CheckInLocation? = nil,
        at date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        var lines: [String] = []
        switch status {
        case .safe: lines.append("CHECK-IN: I'm safe.")
        case .needHelp: lines.append("CHECK-IN: I need help.")
        }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            lines.append(String(note.prefix(maxNoteLength)))
        }
        if let location {
            let lat = String(format: "%.4f", location.latitude)
            let lon = String(format: "%.4f", location.longitude)
            lines.append("Location: \(lat), \(lon) (maps: https://maps.apple.com/?ll=\(lat),\(lon))")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mm a zzz"
        lines.append("Sent \(formatter.string(from: date)) with Meshline")
        return lines.joined(separator: "\n")
    }
}

/// Invite copy for the share sheet and Messages.
enum MeshlineInvite {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6829302130")!

    static var message: String {
        "Join me on Meshline. It's a free, open source messenger that keeps working with no internet or cell service, "
            + "by passing encrypted messages phone to phone over Bluetooth. Good to have before an emergency. "
            + "Get it: \(appStoreURL.absoluteString) "
            + "(if that link doesn't open yet, use the beta: \(MeshlineShareLink.url.absoluteString))"
    }
}

/// After the first message is sent, ask once to invite three people.
final class InviteNudge: ObservableObject {
    static let shared = InviteNudge()
    static let sentKey = "meshline.sentMessageCount"
    static let shownKey = "meshline.inviteNudgeShown"

    @Published var isShowing = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasShown: Bool { defaults.bool(forKey: Self.shownKey) }

    /// Call after the user sends a message. Returns true when the nudge
    /// should be shown now (exactly once, after the first message).
    @discardableResult
    func recordMessageSent() -> Bool {
        let count = defaults.integer(forKey: Self.sentKey) + 1
        defaults.set(count, forKey: Self.sentKey)
        guard !hasShown else { return false }
        defaults.set(true, forKey: Self.shownKey)
        DispatchQueue.main.async { self.isShowing = true }
        return true
    }
}

enum NearbyCounter {
    /// People other than me that a message can reach right now.
    static func count(_ rows: [MeshPeerRow]) -> Int {
        rows.filter { !$0.isMe && !$0.isBlocked && ($0.isConnected || $0.isReachable) }.count
    }

    static func text(_ count: Int) -> String {
        switch count {
        case 0: return "No other Meshline users within reach right now"
        case 1: return "1 Meshline user within reach"
        default: return "\(count) Meshline users within reach"
        }
    }
}
