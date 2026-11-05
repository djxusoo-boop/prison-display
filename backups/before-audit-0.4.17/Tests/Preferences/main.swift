import Foundation
let suite = "PrisonDisplayTests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var p = DisplayPreferences(defaults: defaults)
assert(p.mode == 0 && p.resolution == 0 && p.fps == 0 && p.quality == 0)
let compatible = DisplayPreferences(defaults: defaults, compatibilityDefaults: true)
assert(compatible.resolution == 1 && compatible.fps == 1)
print("PASS: new High Sierra setup starts at 720p30 without changing other platforms")
p.cursor = 1; p.mode = 1; p.resolution = 2; p.fps = 1; p.quality = 2; p.save(defaults: defaults)
assert(DisplayPreferences(defaults: UserDefaults(suiteName: suite)!) == p)
assert(DisplayPreferences(defaults: defaults, compatibilityDefaults: true) == p)
print("PASS: compatible defaults preserve every previously saved setting")
defaults.set(3, forKey: "PrisonDisplay.settings.cursor")
defaults.set(-1, forKey: "PrisonDisplay.settings.mode")
defaults.set(99, forKey: "PrisonDisplay.settings.resolution")
let recovered = DisplayPreferences(defaults: defaults)
assert(recovered.cursor == 0 && recovered.mode == 0 && recovered.resolution == 0 && recovered.fps == 1)
for selected in VideoQualityProfile.all.indices {
    var choice = DisplayPreferences(defaults: defaults); choice.quality = selected; choice.save(defaults: defaults)
    assert(DisplayPreferences(defaults: defaults).quality == selected)
}
assert(VideoQualityProfile.all.map { $0.ceiling } == [12_000_000,6_000_000,20_000_000,40_000_000])
print("PASS: all quality ceilings persist; earlier indexes retain their meaning")
print("PASS: preferences persist and invalid saved indexes recover safely")
var input = ReceiverPreferences(defaults: defaults)
assert(!input.keyboard && !input.crossing)
input.keyboard = true; input.crossing = true; input.edge = 3; input.save(defaults: defaults)
assert(ReceiverPreferences(defaults: UserDefaults(suiteName: suite)!) == input)
print("PASS: input choices and crossing edge survive app relaunch")
defaults.set(999, forKey: "desktopEdge")
assert(ReceiverPreferences(defaults: defaults).edge == 0)
print("PASS: corrupt crossing edge recovers to a valid choice")

var secondary = DisplayPreferences(defaults: defaults, screenSlot: 1)
secondary.resolution = 1; secondary.fps = 1; secondary.quality = 2
let firstBefore = DisplayPreferences(defaults: defaults)
secondary.save(defaults: defaults, screenSlot: 1)
assert(DisplayPreferences(defaults: defaults) == firstBefore)
assert(DisplayPreferences(defaults: defaults, screenSlot: 1) == secondary)
print("PASS: each simultaneous screen retains its own settings")
var legacyQueries = 0
assert(ScreenCaptureAccess.permitted(systemMajor: 10, query: { legacyQueries += 1; return false }))
assert(legacyQueries == 0)
assert(ScreenCaptureAccess.permitted(systemMajor: 10, query: nil))
assert(!ScreenCaptureAccess.permitted(systemMajor: 11, query: nil))
assert(!ScreenCaptureAccess.permitted(systemMajor: 11, query: { false }))
assert(ScreenCaptureAccess.permitted(systemMajor: 11, query: { true }))
print("PASS: Catalina never calls unavailable permission API; modern capture fails closed")
