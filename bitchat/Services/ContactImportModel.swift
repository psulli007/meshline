//
// ContactImportModel.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//
// "Find friends from my Contacts": hashes each contact's numbers on this
// phone and matches them against phone hashes heard from nearby Meshline
// users. Contact names and numbers never leave the phone; only the hash
// list (no numbers) is kept so later matches can happen in the background.
//

import BitFoundation
import Combine
import Foundation
#if canImport(Contacts)
import Contacts
#endif

struct ImportedContact: Identifiable, Equatable {
    let id: String
    let name: String
    /// First usable number, kept in memory only, for the Invite text.
    let number: String
    let hashes: [Data]
}

@MainActor
final class ContactImportModel: ObservableObject {
    static let shared = ContactImportModel()
    static let hashesKey = "meshline.importedContactHashes"
    static let matchedKey = "meshline.phoneMatchedFingerprints"
    static let maxStoredHashes = 5000

    @Published private(set) var unmatched: [ImportedContact] = []
    @Published private(set) var isImporting = false
    @Published private(set) var lastError: String?
    @Published private(set) var phoneMatched: Set<String>

    private let defaults: UserDefaults
    private let directory: PhoneMatchDirectory
    private var cancellable: AnyCancellable?
    private var lastImport: [ImportedContact] = []

    init(defaults: UserDefaults = .standard, directory: PhoneMatchDirectory = .shared) {
        self.defaults = defaults
        self.directory = directory
        phoneMatched = Set(defaults.stringArray(forKey: Self.matchedKey) ?? [])
        cancellable = NotificationCenter.default
            .publisher(for: PhoneMatchDirectory.didRecordNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.matchStored() }
    }

    /// hash hex -> contact name.
    private var storedHashes: [String: String] {
        defaults.dictionary(forKey: Self.hashesKey) as? [String: String] ?? [:]
    }

    func isPhoneMatched(fingerprint: String) -> Bool {
        phoneMatched.contains(fingerprint)
    }

    #if canImport(Contacts)
    func importContacts() {
        guard !isImporting else { return }
        isImporting = true
        lastError = nil
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { [weak self] granted, _ in
            guard granted else {
                Task { @MainActor in
                    self?.isImporting = false
                    self?.lastError = "Meshline can't see your Contacts. You can allow it in Settings."
                }
                return
            }
            let contacts = Self.readContacts(store)
            Task { @MainActor in
                self?.finishImport(contacts)
            }
        }
    }

    nonisolated private static func readContacts(_ store: CNContactStore) -> [ImportedContact] {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        var result: [ImportedContact] = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        try? store.enumerateContacts(with: request) { contact, _ in
            let numbers = contact.phoneNumbers.map(\.value.stringValue)
            let hashes = numbers.compactMap { PhoneNumberHasher.hash(raw: $0) }
            guard let first = numbers.first, !hashes.isEmpty else { return }
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? first
            result.append(ImportedContact(id: contact.identifier, name: name, number: first, hashes: hashes))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    #endif

    func finishImport(_ contacts: [ImportedContact]) {
        var stored = storedHashes
        for contact in contacts {
            for hash in contact.hashes where stored.count < Self.maxStoredHashes {
                stored[hash.hexEncodedString()] = contact.name
            }
        }
        defaults.set(stored, forKey: Self.hashesKey)
        lastImport = contacts
        isImporting = false
        matchStored()
    }

    /// Match every stored hash against what has been heard nearby.
    func matchStored() {
        var matchedHashes = Set<Data>()
        for (hex, name) in storedHashes {
            guard let hash = Data(hexString: hex), let entry = directory.entry(for: hash) else { continue }
            matchedHashes.insert(hash)
            let fingerprint = entry.noisePublicKey.sha256Fingerprint()
            if !phoneMatched.contains(fingerprint) {
                phoneMatched.insert(fingerprint)
                FavoritesPersistenceService.shared.addFavorite(
                    peerNoisePublicKey: entry.noisePublicKey,
                    peerNickname: entry.nickname
                )
                if ContactLabelStore.shared.label(for: fingerprint) == nil {
                    ContactLabelStore.shared.setLabel(name, for: fingerprint)
                }
            }
        }
        defaults.set(Array(phoneMatched), forKey: Self.matchedKey)
        unmatched = lastImport.filter { contact in
            !contact.hashes.contains(where: matchedHashes.contains)
        }
    }

    func removeAll() {
        defaults.removeObject(forKey: Self.hashesKey)
        defaults.removeObject(forKey: Self.matchedKey)
        phoneMatched = []
        unmatched = []
        lastImport = []
        directory.removeAll()
    }

    /// sms: link that opens Messages with the invite filled in.
    static func inviteURL(number: String) -> URL? {
        let digits = number.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?")
        let body = MeshlineInvite.message.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "sms:\(digits)&body=\(body)")
    }
}
