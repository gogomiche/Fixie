import XCTest
@testable import Fixie

final class KeychainManagerTests: XCTestCase {

    private let testKey = "test_key_\(UUID().uuidString)"
    private let keychain = KeychainManager.shared

    override func tearDown() {
        super.tearDown()
        // Clean up test key
        keychain.delete(key: testKey)
    }

    // MARK: - Save and Retrieve Tests

    func testKeychain_saveAndRetrieve() {
        let testValue = "test_api_key_12345"

        let saveResult = keychain.save(testValue, forKey: testKey)
        XCTAssertTrue(saveResult)

        let retrievedValue = keychain.get(key: testKey)
        XCTAssertEqual(retrievedValue, testValue)
    }

    func testKeychain_overwriteExisting() {
        let originalValue = "original_value"
        let newValue = "new_value"

        keychain.save(originalValue, forKey: testKey)
        keychain.save(newValue, forKey: testKey)

        let retrievedValue = keychain.get(key: testKey)
        XCTAssertEqual(retrievedValue, newValue)
    }

    func testKeychain_getNonExistentKey() {
        let result = keychain.get(key: "non_existent_key_\(UUID().uuidString)")
        XCTAssertNil(result)
    }

    // MARK: - Delete Tests

    func testKeychain_deleteExisting() {
        keychain.save("test", forKey: testKey)

        let deleteResult = keychain.delete(key: testKey)
        XCTAssertTrue(deleteResult)

        let retrievedValue = keychain.get(key: testKey)
        XCTAssertNil(retrievedValue)
    }

    func testKeychain_deleteNonExistent() {
        let deleteResult = keychain.delete(key: "non_existent_key_\(UUID().uuidString)")
        // Should return true (errSecItemNotFound is acceptable)
        XCTAssertTrue(deleteResult)
    }

    // MARK: - Exists Tests

    func testKeychain_existsTrue() {
        keychain.save("test", forKey: testKey)

        let exists = keychain.exists(key: testKey)
        XCTAssertTrue(exists)
    }

    func testKeychain_existsFalse() {
        let exists = keychain.exists(key: "non_existent_key_\(UUID().uuidString)")
        XCTAssertFalse(exists)
    }

    // MARK: - Special Characters Tests

    func testKeychain_specialCharacters() {
        let specialValue = "test!@#$%^&*()_+-=[]{}|;':\",./<>?"

        keychain.save(specialValue, forKey: testKey)
        let retrievedValue = keychain.get(key: testKey)

        XCTAssertEqual(retrievedValue, specialValue)
    }

    func testKeychain_unicodeValue() {
        let unicodeValue = "テスト日本語🔐"

        keychain.save(unicodeValue, forKey: testKey)
        let retrievedValue = keychain.get(key: testKey)

        XCTAssertEqual(retrievedValue, unicodeValue)
    }

    func testKeychain_emptyValue() {
        let emptyValue = ""

        keychain.save(emptyValue, forKey: testKey)
        let retrievedValue = keychain.get(key: testKey)

        XCTAssertEqual(retrievedValue, emptyValue)
    }
}
