//
// MeshlineRangeTests.swift
// bitchatTests
//
// Meshline range features: 10-hop TTL, dense-area probabilistic relay,
// and 72-hour store-and-forward.
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct MeshlineRangeTests {
    private func decide(ttl: UInt8, degree: Int, isAnnounce: Bool = false, roll: Double = 0) -> RelayDecision {
        RelayController.decide(
            ttl: ttl,
            senderIsSelf: false,
            isEncrypted: false,
            isDirectedEncrypted: false,
            isFragment: false,
            isDirectedFragment: false,
            isHandshake: false,
            isAnnounce: isAnnounce,
            degree: degree,
            highDegreeThreshold: TransportConfig.bleHighDegreeThreshold,
            relayRoll: roll
        )
    }

    @Test func defaultTTLIsTenHops() {
        #expect(TransportConfig.messageTTLDefault == 10)
        #expect(TransportConfig.bleFragmentRelayTtlCap == 10)
    }

    @Test func thinChainRelaysAndDecrements() {
        let d = decide(ttl: 10, degree: 1)
        #expect(d.shouldRelay)
        #expect(d.newTTL == 8)
        let mid = decide(ttl: 5, degree: 2)
        #expect(mid.shouldRelay)
        #expect(mid.newTTL == 4)
    }

    @Test func ttlAboveDefaultIsClamped() {
        let d = decide(ttl: 255, degree: 1)
        #expect(d.newTTL <= TransportConfig.messageTTLDefault - 1)
    }

    @Test func multiHopChainEventuallyStops() {
        var ttl: UInt8 = TransportConfig.messageTTLDefault
        var hops = 0
        while true {
            let d = decide(ttl: ttl, degree: 2)
            guard d.shouldRelay else { break }
            ttl = d.newTTL
            hops += 1
            #expect(hops < 20)
            if hops >= 20 { break }
        }
        #expect(hops >= 6)
    }

    @Test func denseAreasRelayProbabilistically() {
        let t = TransportConfig.bleHighDegreeThreshold
        #expect(RelayController.denseRelayProbability(degree: 1, highDegreeThreshold: t, isAnnounce: false, isUrgentBoardPost: false) == 1.0)
        #expect(RelayController.denseRelayProbability(degree: t, highDegreeThreshold: t, isAnnounce: false, isUrgentBoardPost: false) == 0.7)
        #expect(RelayController.denseRelayProbability(degree: t * 2, highDegreeThreshold: t, isAnnounce: false, isUrgentBoardPost: false) == 0.5)
        #expect(RelayController.denseRelayProbability(degree: t * 3, highDegreeThreshold: t, isAnnounce: true, isUrgentBoardPost: false) == 1.0)
        #expect(!decide(ttl: 7, degree: t * 2, roll: 0.9).shouldRelay)
        #expect(decide(ttl: 7, degree: t * 2, roll: 0.1).shouldRelay)
        #expect(decide(ttl: 7, degree: t * 2, isAnnounce: true, roll: 0.99).shouldRelay)
    }

    // MARK: 72 hour carry-forward

    private static let base = Date(timeIntervalSince1970: 1_750_000_000)
    private let recipient = Data(repeating: 0xB0, count: 32)

    private func envelope(sealedAt: Date, lifetime: TimeInterval) -> CourierEnvelope {
        CourierEnvelope(
            recipientTag: CourierEnvelope.recipientTag(noiseStaticKey: recipient, epochDay: CourierEnvelope.epochDay(for: sealedAt)),
            expiry: UInt64((sealedAt.timeIntervalSince1970 + lifetime) * 1000),
            ciphertext: Data((0..<64).map { _ in UInt8.random(in: 0...255) })
        )
    }

    @Test func courierLifetimeIs72Hours() {
        #expect(CourierEnvelope.maxLifetimeSeconds == 72 * 60 * 60)
    }

    @Test func courierAcceptsSeventyHourMailAndRejectsBeyondPolicy() {
        let store = CourierStore(persistsToDisk: false, now: { Self.base })
        let ok = store.deposit(envelope(sealedAt: Self.base, lifetime: 70 * 3600), from: Data(repeating: 1, count: 32))
        #expect(ok)
        let tooLong = store.deposit(envelope(sealedAt: Self.base, lifetime: 80 * 3600), from: Data(repeating: 2, count: 32))
        #expect(!tooLong)
    }

    @Test func carriedMailStillDeliversOnDayThreeThenExpires() {
        final class Clock { var now = MeshlineRangeTests.base }
        let clock = Clock()
        let store = CourierStore(persistsToDisk: false, now: { clock.now })
        let env = envelope(sealedAt: Self.base, lifetime: 72 * 3600)
        #expect(store.deposit(env, from: Data(repeating: 1, count: 32)))
        clock.now = Self.base.addingTimeInterval(71 * 3600)
        #expect(store.takeEnvelopes(for: recipient).count == 1)

        let env2 = envelope(sealedAt: Self.base, lifetime: 72 * 3600)
        clock.now = Self.base
        #expect(store.deposit(env2, from: Data(repeating: 1, count: 32)))
        clock.now = Self.base.addingTimeInterval(73 * 3600)
        #expect(store.takeEnvelopes(for: recipient).isEmpty)
    }

    @Test func recipientTagsCoverThreeDaysBack() {
        let sealed = Self.base
        let tag = CourierEnvelope.recipientTag(noiseStaticKey: recipient, epochDay: CourierEnvelope.epochDay(for: sealed))
        let later = sealed.addingTimeInterval(71 * 3600)
        #expect(CourierEnvelope.candidateTags(noiseStaticKey: recipient, around: later).contains(tag))
    }
}
