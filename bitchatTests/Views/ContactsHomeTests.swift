//
// ContactsHomeTests.swift
// bitchatTests
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct ContactsHomeTests {
    private func row(
        _ id: String,
        name: String = "x",
        isMe: Bool = false,
        isBlocked: Bool = false,
        isFavorite: Bool = false,
        isConnected: Bool = false,
        isReachable: Bool = false,
        status: EncryptionStatus = .noHandshake
    ) -> MeshPeerRow {
        MeshPeerRow(
            peerID: PeerID(str: id),
            displayName: name,
            isMe: isMe,
            hasUnread: false,
            isBlocked: isBlocked,
            isFavorite: isFavorite,
            isConnected: isConnected,
            isReachable: isReachable,
            isMutualFavorite: false,
            encryptionStatus: status,
            showsVerifiedBadgeWhenOffline: false,
            showsVouchedBadge: false
        )
    }

    @Test
    func sections_splitSavedAndNearby() async {
        let rows = [
            row("0000000000000001", isMe: true, isConnected: true),
            row("0000000000000002", name: "Zed", isFavorite: true),
            row("0000000000000003", name: "amy", isFavorite: true, isReachable: true),
            row("0000000000000004", isConnected: true, isReachable: true),
            row("0000000000000005", isConnected: true, status: .noiseVerified),
            row("0000000000000006", isBlocked: true, isFavorite: true, isConnected: true),
            row("0000000000000007")
        ]
        let contacts = ContactsHomeSections.contacts(rows).map(\.peerID.id)
        #expect(contacts.count == 3)
        // Reachable first, then by name.
        #expect(contacts.first == PeerID(str: "0000000000000003").id)
        #expect(contacts.contains(PeerID(str: "0000000000000005").id))
        #expect(ContactsHomeSections.nearby(rows).map(\.peerID.id) == [PeerID(str: "0000000000000004").id])
    }

    @Test
    func labelStore_trimsPersistsAndClears() async {
        let suite = "ContactsHomeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ContactLabelStore(defaults: defaults)
        store.setLabel("  Mom  ", for: "fp1")
        #expect(store.label(for: "fp1") == "Mom")
        #expect(ContactLabelStore(defaults: defaults).label(for: "fp1") == "Mom")

        store.setLabel("   ", for: "fp1")
        #expect(store.label(for: "fp1") == nil)

        store.setLabel(String(repeating: "a", count: 200), for: "fp2")
        #expect(store.label(for: "fp2")?.count == ContactLabelStore.maxLabelLength)

        store.removeAll()
        #expect(ContactLabelStore(defaults: defaults).labels.isEmpty)
    }

    @Test
    func invite_hasLinkAndNoEmDash() async {
        let message = MeshlineInvite.message
        #expect(message.contains(MeshlineShareLink.url.absoluteString))
        #expect(!message.contains("\u{2014}"))
    }
}
