//
// PhoneMatchingTests.swift
// bitchatTests
//

import BitFoundation
import Foundation
import Testing
@testable import bitchat

struct PhoneMatchingTests {
    @Test
    func normalize_handlesCommonFormats() {
        #expect(PhoneNumberHasher.normalize("(415) 555-0123") == "+14155550123")
        #expect(PhoneNumberHasher.normalize("1 415 555 0123") == "+14155550123")
        #expect(PhoneNumberHasher.normalize("+44 20 7946 0958") == "+442079460958")
        #expect(PhoneNumberHasher.normalize("0044 20 7946 0958") == "+442079460958")
        #expect(PhoneNumberHasher.normalize("555-0123") == nil)
        #expect(PhoneNumberHasher.normalize("") == nil)
    }

    @Test
    func hash_sameNumberDifferentFormatsMatch() {
        let a = PhoneNumberHasher.hash(raw: "(415) 555-0123")
        let b = PhoneNumberHasher.hash(raw: "+1 415-555-0123")
        #expect(a != nil)
        #expect(a == b)
        #expect(a?.count == 16)
        #expect(a != PhoneNumberHasher.hash(raw: "+1 415-555-0124"))
    }

    @Test
    func announcement_roundTripsPhoneHash() throws {
        let hash = try #require(PhoneNumberHasher.hash(raw: "+14155550123"))
        let packet = AnnouncementPacket(
            nickname: "mom",
            noisePublicKey: Data(repeating: 1, count: 32),
            signingPublicKey: Data(repeating: 2, count: 32),
            directNeighbors: nil,
            phoneHash: hash
        )
        let encoded = try #require(packet.encode())
        let decoded = try #require(AnnouncementPacket.decode(from: encoded))
        #expect(decoded.phoneHash == hash)
        #expect(decoded.nickname == "mom")
    }

    @Test
    func directory_recordsAndLooksUp() {
        let directory = PhoneMatchDirectory()
        let hash = Data(repeating: 7, count: 16)
        directory.record(hash: hash, noisePublicKey: Data([1, 2, 3]), nickname: "a")
        #expect(directory.entry(for: hash)?.nickname == "a")
        directory.record(hash: Data([1]), noisePublicKey: Data([1]), nickname: "bad")
        #expect(directory.entry(for: Data([1])) == nil)
    }

    @Test @MainActor
    func inviteURL_opensMessagesWithLink() throws {
        let url = try #require(ContactImportModel.inviteURL(number: "(415) 555-0123"))
        #expect(url.absoluteString.hasPrefix("sms:4155550123&body="))
        #expect(url.absoluteString.contains("testflight.apple.com"))
    }
}
