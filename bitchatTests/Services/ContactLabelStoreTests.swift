//
// ContactLabelStoreTests.swift
// bitchatTests
//

import Foundation
import Testing
@testable import bitchat

struct ContactLabelStoreTests {
    private func defaults() -> UserDefaults {
        let name = "meshline.tests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func savesTrimsAndPersists() {
        let d = defaults()
        let store = ContactLabelStore(defaults: d)
        store.setLabel("  Mom  ", for: "fp1")
        #expect(store.label(for: "fp1") == "Mom")
        #expect(ContactLabelStore(defaults: d).label(for: "fp1") == "Mom")
    }

    @Test func emptyRemovesAndLongIsCapped() {
        let store = ContactLabelStore(defaults: defaults())
        store.setLabel("Mom", for: "fp1")
        store.setLabel("   ", for: "fp1")
        #expect(store.label(for: "fp1") == nil)
        store.setLabel(String(repeating: "a", count: 500), for: "fp2")
        #expect(store.label(for: "fp2")?.count == ContactLabelStore.maxLabelLength)
    }

    @Test func removeAllWipes() {
        let d = defaults()
        let store = ContactLabelStore(defaults: d)
        store.setLabel("Mom", for: "fp1")
        store.removeAll()
        #expect(ContactLabelStore(defaults: d).labels.isEmpty)
    }
}
