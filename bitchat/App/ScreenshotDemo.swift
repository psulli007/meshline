//
// ScreenshotDemo.swift
// Meshline
//
// DEBUG builds only. Seeds sample people, a group and public chat messages
// into the real UI so App Store screenshots can be captured on the iOS
// Simulator, which has no Bluetooth. Activated only by the launch argument
// "-MeshlineScreenshot <people|chat|qr|group>". Never compiled into Release.
//

#if DEBUG
import BitFoundation
import Foundation

enum ScreenshotDemo {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-MeshlineScreenshot"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static var isActive: Bool { screen != nil }

    static let groupPeerID = PeerID(groupID: Data((0..<16).map { UInt8($0 + 1) }))

    private static let people: [(hex: String, name: String, connected: Bool, reachable: Bool, verified: Bool, unread: Bool)] = [
        ("a1b2c3d4e5f60718", "Mom", true, true, true, true),
        ("b2c3d4e5f6071829", "Dad", false, true, true, false),
        ("c3d4e5f60718293a", "Sam", true, true, false, false),
        ("d4e5f60718293a4b", "Priya", false, false, true, false),
    ]

    static func meshRows(myPeerID: PeerID, myName: String) -> [MeshPeerRow] {
        var rows = people.map { p in
            MeshPeerRow(
                peerID: PeerID(str: p.hex), displayName: p.name, isMe: false, hasUnread: p.unread,
                isBlocked: false, isFavorite: true, isConnected: p.connected, isReachable: p.reachable,
                isMutualFavorite: true, encryptionStatus: p.verified && p.connected ? .noiseVerified : .noiseSecured,
                showsVerifiedBadgeWhenOffline: p.verified && !p.connected, showsVouchedBadge: false
            )
        }
        rows.append(MeshPeerRow(
            peerID: PeerID(str: "e5f60718293a4b5c"), displayName: "Jordan", isMe: false, hasUnread: false,
            isBlocked: false, isFavorite: false, isConnected: true, isReachable: true, isMutualFavorite: false,
            encryptionStatus: .noiseSecured, showsVerifiedBadgeWhenOffline: false, showsVouchedBadge: false
        ))
        return rows
    }

    static func groupRows() -> [GroupChatRow] {
        [GroupChatRow(peerID: groupPeerID, name: "Family", memberCount: 4, isCreator: true, hasUnread: true)]
    }

    static let groupMembers = ["You", "Mom", "Dad", "Sam"]

    static func publicMessages() -> [BitchatMessage] {
        let now = Date()
        let lines: [(String, String, String, TimeInterval)] = [
            ("Sam", "c3d4e5f60718293a", "Power is out on our whole block. Anyone have cell service?", -540),
            ("Priya", "d4e5f60718293a4b", "No service here either. Meshline still works though, this hopped through 3 phones to reach you.", -420),
            ("Jordan", "e5f60718293a4b5c", "Community center on Main St has water and a generator.", -300),
            ("Mom", "a1b2c3d4e5f60718", "Thanks Jordan. Heading there now with Dad.", -180),
            ("Sam", "c3d4e5f60718293a", "Will meet you there. Stay safe everyone.", -60),
        ]
        return lines.map { s in
            BitchatMessage(sender: s.0, content: s.2, timestamp: now.addingTimeInterval(s.3), isRelay: false,
                           senderPeerID: PeerID(str: s.1))
        }
    }

    @MainActor
    static func seed(conversations: ConversationStore) {
        guard isActive else { return }
        for m in publicMessages() { _ = conversations.append(m, to: .mesh) }
    }
}
#endif

/// Always false in Release builds.
enum ScreenshotMode {
    static var isActive: Bool {
        #if DEBUG
        return ScreenshotDemo.isActive
        #else
        return false
        #endif
    }
}
