//
// PhoneMatching.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//
// Find friends by phone number with no internet and no SMS. Each user types
// their own number (unverified). Announces carry only a salted hash of it,
// so nearby phones can match it against their address book.
//
// Honest limits: anyone can claim any number, so matches are labeled
// unverified until checked in person by QR. Phone numbers are a small space,
// so a determined attacker can brute force a hash back to a number; the hash
// keeps numbers out of plain sight, it is not strong secrecy.
//

import BitFoundation
import CryptoKit
import Foundation

enum PhoneNumberHasher {
    static let salt = "meshline.phone-match.v1|"
    static let hashLength = 16

    /// Best effort E.164 without a phone library: keeps digits; 10 digits
    /// (or 11 starting with 1) are treated as US/Canada numbers.
    static func normalize(_ raw: String, defaultCountryCode: String = "1") -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadPlus = trimmed.hasPrefix("+")
        var digits = trimmed.filter(\.isASCII).filter(\.isNumber)
        if !hadPlus, digits.hasPrefix("00") { digits.removeFirst(2); return validated("+" + digits) }
        if hadPlus { return validated("+" + digits) }
        if digits.count == 10 { return validated("+" + defaultCountryCode + digits) }
        if digits.count == 11, digits.hasPrefix(defaultCountryCode) { return validated("+" + digits) }
        return nil
    }

    private static func validated(_ e164: String) -> String? {
        let count = e164.count - 1
        return (8...15).contains(count) ? e164 : nil
    }

    static func hash(e164: String) -> Data {
        Data(SHA256.hash(data: Data((salt + e164).utf8)).prefix(hashLength))
    }

    static func hash(raw: String) -> Data? {
        normalize(raw).map { hash(e164: $0) }
    }
}

/// The user's own number, stored only on this phone.
enum MyPhoneNumber {
    static let numberKey = "meshline.myPhoneNumber"
    static let askedKey = "meshline.myPhoneNumberAsked"

    static var stored: String? {
        UserDefaults.standard.string(forKey: numberKey)
    }

    /// The hash put in announces, or nil when no number was given.
    static var announceHash: Data? {
        stored.flatMap { PhoneNumberHasher.hash(raw: $0) }
    }

    static var wasAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    @discardableResult
    static func save(_ raw: String?) -> Bool {
        UserDefaults.standard.set(true, forKey: askedKey)
        guard let raw, let e164 = PhoneNumberHasher.normalize(raw) else {
            UserDefaults.standard.removeObject(forKey: numberKey)
            return raw == nil || raw?.isEmpty == true
        }
        UserDefaults.standard.set(e164, forKey: numberKey)
        return true
    }

    static func wipe() {
        UserDefaults.standard.removeObject(forKey: numberKey)
        UserDefaults.standard.removeObject(forKey: askedKey)
    }
}

/// Phone hashes seen in signed announces: hash -> the peer's Noise key and
/// nickname. Thread safe; written from BLE queues, read on the main thread.
final class PhoneMatchDirectory: @unchecked Sendable {
    static let shared = PhoneMatchDirectory()
    static let didRecordNotification = Notification.Name("meshline.phoneMatch.didRecord")
    static let maxEntries = 1000

    struct Entry: Equatable {
        let noisePublicKey: Data
        let nickname: String
        let lastSeen: Date
    }

    private let lock = NSLock()
    private var entries: [Data: Entry] = [:]

    func record(hash: Data, noisePublicKey: Data, nickname: String, now: Date = Date()) {
        guard hash.count == PhoneNumberHasher.hashLength, !noisePublicKey.isEmpty else { return }
        lock.lock()
        let isNew = entries[hash]?.noisePublicKey != noisePublicKey
        entries[hash] = Entry(noisePublicKey: noisePublicKey, nickname: nickname, lastSeen: now)
        if entries.count > Self.maxEntries,
           let oldest = entries.min(by: { $0.value.lastSeen < $1.value.lastSeen })?.key {
            entries[oldest] = nil
        }
        lock.unlock()
        if isNew {
            NotificationCenter.default.post(name: Self.didRecordNotification, object: nil)
        }
    }

    func entry(for hash: Data) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        return entries[hash]
    }

    func removeAll() {
        lock.lock(); entries = [:]; lock.unlock()
    }
}
