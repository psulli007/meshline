//
// MeshlineSafetyTests.swift
// bitchatTests
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct MeshlineSafetyTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let utc = TimeZone(identifier: "UTC")!

    @Test func safeCheckInText() {
        let text = SafetyCheckIn.message(status: .safe, at: date, timeZone: utc)
        #expect(text.hasPrefix("CHECK-IN: I'm safe."))
        #expect(text.contains("Sent "))
        #expect(!text.contains("Location"))
        #expect(!text.contains("\u{2014}"))
    }

    @Test func helpCheckInWithNoteAndLocation() {
        let text = SafetyCheckIn.message(
            status: .needHelp,
            note: "  Ankle hurt, at the school gym  ",
            location: CheckInLocation(latitude: 40.712776, longitude: -74.005974),
            at: date,
            timeZone: utc
        )
        #expect(text.hasPrefix("CHECK-IN: I need help."))
        #expect(text.contains("Ankle hurt, at the school gym\n"))
        #expect(text.contains("Location: 40.7128, -74.0060"))
        #expect(text.contains("maps.apple.com/?ll=40.7128,-74.0060"))
    }

    @Test func longNoteIsCapped() {
        let text = SafetyCheckIn.message(status: .safe, note: String(repeating: "x", count: 1000), at: date)
        #expect(text.count < 400)
        #expect(text.count <= InputValidator.Limits.maxMessageLength)
    }

    @Test func inviteTextExplainsAndLinks() {
        let text = MeshlineInvite.message
        #expect(text.contains("https://apps.apple.com/app/id6829302130"))
        #expect(text.contains("testflight.apple.com"))
        #expect(text.contains("no internet"))
        #expect(!text.contains("\u{2014}"))
    }

    @Test func inviteNudgeShowsOnceAfterFirstMessage() {
        let defaults = UserDefaults(suiteName: "meshline.nudge.\(UUID().uuidString)")!
        let nudge = InviteNudge(defaults: defaults)
        #expect(nudge.recordMessageSent())
        #expect(!nudge.recordMessageSent())
        #expect(!InviteNudge(defaults: defaults).recordMessageSent())
    }

    private func row(_ id: String, me: Bool = false, blocked: Bool = false, connected: Bool = false, reachable: Bool = false) -> MeshPeerRow {
        MeshPeerRow(
            peerID: PeerID(str: id),
            displayName: id,
            isMe: me,
            hasUnread: false,
            isBlocked: blocked,
            isFavorite: false,
            isConnected: connected,
            isReachable: reachable,
            isMutualFavorite: false,
            encryptionStatus: .noHandshake,
            showsVerifiedBadgeWhenOffline: false,
            showsVouchedBadge: false
        )
    }

    @Test func nearbyCounterCountsReachableOthers() {
        let rows = [
            row("0000000000000001", me: true, connected: true),
            row("0000000000000002", connected: true),
            row("0000000000000003", reachable: true),
            row("0000000000000004"),
            row("0000000000000005", blocked: true, connected: true),
        ]
        #expect(NearbyCounter.count(rows) == 2)
        #expect(NearbyCounter.text(2) == "2 Meshline users within reach")
        #expect(NearbyCounter.text(1) == "1 Meshline user within reach")
    }

    @Test func emergencyTipsAreBundledAndClean() {
        #expect(EmergencyTips.tips.count >= 6)
        for tip in EmergencyTips.tips {
            #expect(!tip.body.contains("\u{2014}"))
            #expect(!tip.title.isEmpty)
        }
    }
}
