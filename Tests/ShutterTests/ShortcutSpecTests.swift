import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Shutter

@Test func defaultShortcutIsControlOptionCommandD() {
    let spec = ToggleShortcutStore.defaultSpec
    #expect(spec.keyCode == UInt32(kVK_ANSI_D))
    #expect(spec.carbonModifiers == UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey))
    #expect(spec.displayString == "⌃⌥⌘D")
}

@Test func displayStringOrdersModifiersLikeTheSystem() {
    let spec = ShortcutSpec(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(cmdKey) | UInt32(shiftKey),
        keyLabel: "L")
    #expect(spec.displayString == "⇧⌘L")
}

@Test func carbonModifiersMapFromAppKitFlags() {
    let flags: NSEvent.ModifierFlags = [.command, .option]
    #expect(
        ShortcutSpec.carbonModifiers(from: flags)
            == UInt32(cmdKey) | UInt32(optionKey))
    #expect(ShortcutSpec.carbonModifiers(from: []) == 0)
}

@Test func menuKeyEquivalentLowercasesSingleCharacterLabels() {
    let spec = ShortcutSpec(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey),
        keyLabel: "D")
    let equivalent = spec.menuKeyEquivalent
    #expect(equivalent.key == "d")
    #expect(equivalent.modifiers == [.control, .option, .command])
}

@Test func menuKeyEquivalentIsEmptyForUnprintableKeys() {
    let spec = ShortcutSpec(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(cmdKey),
        keyLabel: "Space")
    #expect(spec.menuKeyEquivalent.key == " ")

    let arrow = ShortcutSpec(
        keyCode: UInt32(kVK_LeftArrow),
        carbonModifiers: UInt32(cmdKey),
        keyLabel: "←")
    #expect(arrow.menuKeyEquivalent.key == "←".lowercased())
}

@Test func specSurvivesACodingRoundTrip() throws {
    let spec = ShortcutSpec(
        keyCode: 42, carbonModifiers: UInt32(optionKey), keyLabel: "\\")
    let decoded = try JSONDecoder().decode(
        ShortcutSpec.self, from: JSONEncoder().encode(spec))
    #expect(decoded == spec)
}

/* The private symbols this app prefers must exist on the OS it targets;
   if Apple ever drops them, the scripted fallback takes over silently —
   this test is the tripwire that tells us it happened. */
@Test func skyLightSymbolsResolveOnThisOS() {
    let handle = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    #expect(handle != nil)
    #expect(dlsym(handle, "SLSGetAppearanceThemeLegacy") != nil)
    #expect(dlsym(handle, "SLSSetAppearanceThemeLegacy") != nil)
}
