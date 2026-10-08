import CoreGraphics
import Testing
@testable import Tuck

/// Frames measured on a 14" MacBook Pro running macOS 26 (notch spans x 771…956).
struct PlacementTests {
    let dot = CGRect(x: 1498, y: 0, width: 38, height: 33)
    let separator = CGRect(x: 700, y: 0, width: 12, height: 33)

    @Test func itemRightOfTheDotIsPinned() {
        let clock = CGRect(x: 1578, y: 0, width: 152, height: 33)
        #expect(Placement.of(frame: clock, isOnScreen: true, separator: separator, dot: dot) == .pinned)
    }

    @Test func onScreenItemBetweenSeparatorAndDotIsVisible() {
        let item = CGRect(x: 1035, y: 0, width: 32, height: 33)
        #expect(Placement.of(frame: item, isOnScreen: true, separator: separator, dot: dot) == .visible)
    }

    @Test func offScreenItemBetweenSeparatorAndDotIsBehindTheNotch() {
        let item = CGRect(x: 805, y: 0, width: 38, height: 33)
        #expect(Placement.of(frame: item, isOnScreen: false, separator: separator, dot: dot) == .overflow)
    }

    @Test func itemLeftOfTheSeparatorIsHidden() {
        let item = CGRect(x: 662, y: 0, width: 38, height: 33)
        #expect(Placement.of(frame: item, isOnScreen: false, separator: separator, dot: dot) == .hidden)
    }

    @Test func collapsedSeparatorStillMarksItsLeftSideHidden() {
        let collapsed = CGRect(x: -3518, y: 0, width: 5016, height: 33)
        let hidden = CGRect(x: -3556, y: 0, width: 38, height: 33)
        let visible = CGRect(x: 1498 - 38, y: 0, width: 38, height: 33)
        let dot = CGRect(x: 1498, y: 0, width: 38, height: 33)
        #expect(Placement.of(frame: hidden, isOnScreen: false, separator: collapsed, dot: dot) == .hidden)
        #expect(Placement.of(frame: visible, isOnScreen: true, separator: collapsed, dot: dot) == .visible)
    }

    @Test func withoutControlItemsEverythingIsVisibleOrOverflow() {
        let item = CGRect(x: 900, y: 0, width: 38, height: 33)
        #expect(Placement.of(frame: item, isOnScreen: true, separator: nil, dot: nil) == .visible)
        #expect(Placement.of(frame: item, isOnScreen: false, separator: nil, dot: nil) == .overflow)
    }
}

struct ItemLabelTests {
    @Test func controlCenterModulesUseTheirOwnLabel() {
        let title = ItemLabel.title(appName: "Vezérlőközpont", bundleID: "com.apple.controlcenter", detail: "Wi‑Fi", appHasSeveralItems: true)
        #expect(title == "Wi‑Fi")
    }

    @Test func liveStateAfterACommaIsDropped() {
        let title = ItemLabel.title(appName: "Vezérlőközpont", bundleID: "com.apple.controlcenter", detail: "Wi‑Fi, kapcsolódva, 3 függőleges vonal", appHasSeveralItems: true)
        #expect(title == "Wi‑Fi")
    }

    @Test func weatherUsesAFixedName() {
        let title = ItemLabel.title(appName: "WeatherMenu", bundleID: "com.apple.weather.menu", detail: "részben felhős éjszaka", appHasSeveralItems: false)
        #expect(title == "Weather")
    }

    @Test func singleItemAppsUseTheAppName() {
        let title = ItemLabel.title(appName: "Dropbox", bundleID: "com.getdropbox.dropbox", detail: "Dropbox menu", appHasSeveralItems: false)
        #expect(title == "Dropbox")
    }

    @Test func appsWithSeveralItemsAddTheLabel() {
        let title = ItemLabel.title(appName: "Stats", bundleID: "eu.exelban.Stats", detail: "CPU", appHasSeveralItems: true)
        #expect(title == "Stats — CPU")
    }

    @Test func missingLabelFallsBackToAppName() {
        let title = ItemLabel.title(appName: "Spread", bundleID: "design.uprive.spread", detail: nil, appHasSeveralItems: false)
        #expect(title == "Spread")
    }
}
