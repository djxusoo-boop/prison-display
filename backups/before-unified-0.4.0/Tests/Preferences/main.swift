import Foundation
let suite = "PrisonDisplayTests." + UUID().uuidString
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var p = DisplayPreferences(defaults: defaults)
assert(p.mode == 0 && p.resolution == 0 && p.fps == 0 && p.quality == 0)
p.cursor = 1; p.mode = 1; p.resolution = 2; p.fps = 1; p.quality = 2; p.save(defaults: defaults)
assert(DisplayPreferences(defaults: UserDefaults(suiteName: suite)!) == p)
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
