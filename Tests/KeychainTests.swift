import Foundation
import Security
import Testing
@testable import HFMac

struct KeychainTests {
    @Test func replacementFailurePreservesOldItem() {
        var calls: [String] = []
        let ops = Keychain.Operations(
            update: { _, _ in calls.append("update"); return errSecAuthFailed },
            add: { _ in calls.append("add"); return errSecSuccess },
            delete: { _ in calls.append("delete"); return errSecSuccess })
        do {
            try Keychain.set("synthetic", for: "test", operations: ops)
            Issue.record("Expected save failure")
        } catch {
            #expect((error as? Keychain.SaveError)?.status == errSecAuthFailed)
        }
        #expect(calls == ["update"])
    }

    @Test func updateAndInsert() throws {
        for exists in [true, false] {
            var added = false
            let ops = Keychain.Operations(
                update: { _, attributes in
                    let values = attributes as NSDictionary
                    #expect(values[kSecValueData] as? Data == Data("synthetic".utf8))
                    return exists ? errSecSuccess : errSecItemNotFound
                },
                add: { _ in added = true; return errSecSuccess },
                delete: { _ in Issue.record("Unexpected delete"); return errSecSuccess })
            try Keychain.set("synthetic", for: "test", operations: ops)
            #expect(added == !exists)
        }
    }

    @Test func addFailureIsReported() {
        let ops = Keychain.Operations(update: { _, _ in errSecItemNotFound },
            add: { _ in errSecNotAvailable }, delete: { _ in errSecSuccess })
        #expect(throws: Keychain.SaveError.self) {
            try Keychain.set("synthetic", for: "test", operations: ops)
        }
    }

    @Test func clearingMissingItemSucceedsAndOtherErrorsPropagate() throws {
        for status in [errSecSuccess, errSecItemNotFound, errSecAuthFailed] {
            let ops = Keychain.Operations(
                update: { _, _ in Issue.record("Unexpected update"); return errSecSuccess },
                add: { _ in Issue.record("Unexpected add"); return errSecSuccess },
                delete: { _ in status })
            if status == errSecAuthFailed {
                #expect(throws: Keychain.SaveError.self) {
                    try Keychain.set("", for: "test", operations: ops)
                }
            } else {
                try Keychain.set("", for: "test", operations: ops)
            }
        }
    }
}
