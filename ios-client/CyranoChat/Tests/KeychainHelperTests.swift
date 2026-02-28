// CyranoChat Tests - KeychainHelper

import Testing
import Foundation
@testable import CyranoChat

@Suite("KeychainHelper")
struct KeychainHelperTests {

    // Use a unique test key to avoid interfering with real app data
    private let testKey = "test-key-\(UUID().uuidString)"

    // MARK: - Save and Load

    @Test("Save and load round-trips a value")
    func saveAndLoad() throws {
        let key = "test-roundtrip-\(UUID().uuidString)"
        try KeychainHelper.save(key: key, value: "test-value")

        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == "test-value")

        // Cleanup
        KeychainHelper.delete(key: key)
    }

    @Test("Load returns nil for non-existent key")
    func loadMissing() {
        let loaded = KeychainHelper.load(key: "non-existent-key-\(UUID().uuidString)")
        #expect(loaded == nil)
    }

    @Test("Save overwrites existing value")
    func overwrite() throws {
        let key = "test-overwrite-\(UUID().uuidString)"
        try KeychainHelper.save(key: key, value: "first")
        try KeychainHelper.save(key: key, value: "second")

        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == "second")

        // Cleanup
        KeychainHelper.delete(key: key)
    }

    // MARK: - Delete

    @Test("Delete removes a stored value")
    func delete() throws {
        let key = "test-delete-\(UUID().uuidString)"
        try KeychainHelper.save(key: key, value: "to-delete")

        KeychainHelper.delete(key: key)

        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == nil)
    }

    @Test("Delete does not throw for non-existent key")
    func deleteNonExistent() {
        // Should not crash
        KeychainHelper.delete(key: "does-not-exist-\(UUID().uuidString)")
    }

    // MARK: - Special Characters

    @Test("Handles API key with special characters")
    func specialCharacters() throws {
        let key = "test-special-\(UUID().uuidString)"
        let apiKey = "sk-ant-api03-abc123_XYZ+/=="

        try KeychainHelper.save(key: key, value: apiKey)

        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == apiKey)

        // Cleanup
        KeychainHelper.delete(key: key)
    }

    @Test("Handles empty string value")
    func emptyValue() throws {
        let key = "test-empty-\(UUID().uuidString)"
        try KeychainHelper.save(key: key, value: "")

        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == "")

        // Cleanup
        KeychainHelper.delete(key: key)
    }

    @Test("Handles long value")
    func longValue() throws {
        let key = "test-long-\(UUID().uuidString)"
        let longString = String(repeating: "a", count: 10_000)

        try KeychainHelper.save(key: key, value: longString)

        let loaded = KeychainHelper.load(key: key)
        #expect(loaded == longString)

        // Cleanup
        KeychainHelper.delete(key: key)
    }

    // MARK: - Convenience Property

    @Test("anthropicAPIKey convenience: save, read, delete")
    func convenienceRoundTrip() {
        // Single test for the convenience property to avoid parallel Keychain races
        // 1. Set value
        KeychainHelper.anthropicAPIKey = "sk-convenience-test"

        // 2. Read via convenience getter
        #expect(KeychainHelper.anthropicAPIKey == "sk-convenience-test")

        // 3. Read via raw load
        let raw = KeychainHelper.load(key: KeychainHelper.anthropicAPIKeyName)
        #expect(raw == "sk-convenience-test")

        // 4. Delete via nil setter
        KeychainHelper.anthropicAPIKey = nil
        #expect(KeychainHelper.anthropicAPIKey == nil)
    }
}
