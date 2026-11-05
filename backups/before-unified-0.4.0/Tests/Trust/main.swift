import Foundation
import Security
var failures = 0
func check(_ condition: Bool, _ name: String) { print(condition ? "PASS: \(name)" : "FAIL: \(name)"); if !condition { failures += 1 } }
// A unique account contains only synthetic credentials; no production records are read.
let store = TrustStore(account: "test." + UUID().uuidString)
defer { try? store.forget() }
do {
    var before = DarwinBoolean(false); SecKeychainGetUserInteractionAllowed(&before)
    check(try store.load() == nil, "empty unique test account")
    var after = DarwinBoolean(false); SecKeychainGetUserInteractionAllowed(&after)
    check(before.boolValue == after.boolValue, "passive read restores process interaction policy")
    check(try store.load(allowInteraction: true) == nil, "explicit empty read is permitted without creating a credential")
    SecKeychainGetUserInteractionAllowed(&after)
    check(before.boolValue == after.boolValue, "explicit read restores process interaction policy")
    let first = try TrustedProfile(ConnectionLink(host: "test.local", port: 55000, key: newPairingKey(), serviceName: "Prison-test"))
    try store.save(first)
    check(try store.load() == first, "synthetic credential stored in Keychain")
    check(try store.load(allowInteraction: true) == first, "explicit read recovers only the requested synthetic account")
    let second = try TrustedProfile(ConnectionLink(host: "test.local", port: 55001, key: newPairingKey(), serviceName: "Prison-test"))
    try store.save(second)
    check(try store.load() == second, "existing Keychain credential updated")
    try store.forget(); check(try store.load() == nil, "forget removes only unique test credential")
    try store.forget(); check(true, "forget is idempotent")
} catch { print("FAIL: Keychain test", error); failures += 1 }
print("RESULT", failures, "failures; no production credentials accessed")
exit(failures == 0 ? 0 : 1)
