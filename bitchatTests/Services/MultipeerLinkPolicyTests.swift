//
// MultipeerLinkPolicyTests.swift
// bitchatTests
//

import Testing
import Foundation
@testable import bitchat

struct MultipeerLinkPolicyTests {
    @Test
    func serviceType_isValidBonjourName() async {
        let type = MultipeerLinkPolicy.serviceType
        #expect((1...15).contains(type.count))
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        #expect(type.allSatisfy { allowed.contains($0) })
        #expect(!type.hasPrefix("-") && !type.hasSuffix("-"))
    }

    @Test
    func serviceType_matchesInfoPlistBonjourServices() async throws {
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        // The test host is the app, so its Info.plist must list the service.
        if let services {
            #expect(services.contains("_\(MultipeerLinkPolicy.serviceType)._tcp"))
        }
    }

    @Test
    func shouldInvite_exactlyOneSideInvites() async {
        let a = "ml-0000000000000001"
        let b = "ml-0000000000000002"
        #expect(MultipeerLinkPolicy.shouldInvite(localName: a, remoteName: b))
        #expect(!MultipeerLinkPolicy.shouldInvite(localName: b, remoteName: a))
        #expect(!MultipeerLinkPolicy.shouldInvite(localName: a, remoteName: a))
    }

    @Test
    func acceptsFrame_boundsSize() async {
        #expect(!MultipeerLinkPolicy.acceptsFrame(byteCount: 0))
        #expect(MultipeerLinkPolicy.acceptsFrame(byteCount: 1))
        #expect(MultipeerLinkPolicy.acceptsFrame(byteCount: MultipeerLinkPolicy.maxInboundFrameBytes))
        #expect(!MultipeerLinkPolicy.acceptsFrame(byteCount: MultipeerLinkPolicy.maxInboundFrameBytes + 1))
    }

    @Test
    func randomDisplayName_isNonIdentifyingAndShort() async {
        let name = MultipeerLinkPolicy.randomDisplayName()
        #expect(name.hasPrefix("ml-"))
        #expect(name.count == 19)
        #expect(name != MultipeerLinkPolicy.randomDisplayName())
        // MCPeerID display names must be at most 63 UTF-8 bytes.
        #expect(name.utf8.count <= 63)
    }
}
