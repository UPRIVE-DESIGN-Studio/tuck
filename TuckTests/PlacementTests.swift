import CoreGraphics
import Foundation
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

struct AutoTuckPlannerTests {
    typealias C = AutoTuckPlanner.Candidate
    func key(_ name: String) -> ItemKey { ItemKey(bundleID: name, qualifier: "#0") }
    func item(_ name: String, _ placement: Placement, on: Bool = true, mode: ItemStore.Mode = .auto, rank: Int, width: CGFloat = 30) -> C {
        C(key: key(name), width: width, placement: placement, isOnScreen: on, mode: mode, rank: rank)
    }

    @Test func coveredItemsTuckTheLeastImportantAutoItem() {
        let items = [
            item("a", .overflow, on: false, rank: 0),
            item("b", .visible, rank: 5),
            item("c", .visible, rank: 2),
        ]
        #expect(AutoTuckPlanner.next(items, autoTucked: [], freeWidth: 0) == .tuck(key("b")))
    }

    @Test func showItemsAreNeverTucked() {
        let items = [
            item("a", .overflow, on: false, mode: .show, rank: 9),
            item("b", .visible, mode: .show, rank: 8),
            item("c", .visible, rank: 1),
        ]
        #expect(AutoTuckPlanner.next(items, autoTucked: [], freeWidth: 0) == .tuck(key("c")))
    }

    @Test func nothingToTuckWhenOnlyShowItemsAreCovered() {
        let items = [item("a", .overflow, on: false, mode: .show, rank: 0)]
        #expect(AutoTuckPlanner.next(items, autoTucked: [], freeWidth: 0) == nil)
    }

    @Test func roomBringsBackTheMostImportantAutoTuckedItem() {
        let items = [
            item("a", .hidden, on: false, rank: 7),
            item("b", .hidden, on: false, rank: 3),
            item("c", .visible, rank: 1),
        ]
        let step = AutoTuckPlanner.next(items, autoTucked: [key("a"), key("b")], freeWidth: 100)
        #expect(step == .restore(key("b")))
    }

    @Test func itemsTheUserHidDoNotComeBack() {
        let items = [item("a", .hidden, on: false, mode: .hide, rank: 0)]
        #expect(AutoTuckPlanner.next(items, autoTucked: [], freeWidth: 500) == nil)
    }

    @Test func noRestoreWithoutRoomForTheItemPlusMargin() {
        let items = [item("a", .hidden, on: false, rank: 0, width: 40)]
        #expect(AutoTuckPlanner.next(items, autoTucked: [key("a")], freeWidth: 45) == nil)
        #expect(AutoTuckPlanner.next(items, autoTucked: [key("a")], freeWidth: 60) == .restore(key("a")))
    }

    @Test func hideItemsOnTheVisibleSideGoBackFirst() {
        let items = [
            item("a", .overflow, on: false, rank: 0),
            item("b", .visible, mode: .hide, rank: 1),
            item("c", .visible, rank: 9),
        ]
        #expect(AutoTuckPlanner.next(items, autoTucked: [], freeWidth: 0) == .tuck(key("b")))
    }

    @Test func showItemsInsideTuckComeOutEvenWithoutRoom() {
        let items = [item("a", .hidden, on: false, mode: .show, rank: 0)]
        #expect(AutoTuckPlanner.next(items, autoTucked: [], freeWidth: 0) == .restore(key("a")))
    }

    @Test func coolingItemsWaitBeforeComingBack() {
        let items = [item("a", .hidden, on: false, rank: 0)]
        #expect(AutoTuckPlanner.next(items, autoTucked: [key("a")], freeWidth: 500, cooling: [key("a")]) == nil)
    }
}

struct ItemKeyTests {
    @Test func identifierWinsOverPosition() {
        let keys = ItemKey.keys(for: [("com.apple.controlcenter", "com.apple.menuextra.wifi"), ("eu.stats", nil), ("eu.stats", nil)])
        #expect(keys.map { $0?.rawValue } == ["com.apple.controlcenter|com.apple.menuextra.wifi", "eu.stats|#0", "eu.stats|#1"])
    }

    @Test func unknownOwnerHasNoKey() {
        #expect(ItemKey.keys(for: [(nil, nil)]) == [nil])
    }

    @Test func storeRoundTripsThroughJSON() throws {
        var saved = ItemStore.Saved()
        saved.records["a|#0"] = .init(mode: .hide, trigger: .batteryBelow(percent: 20))
        saved.order = ["a|#0"]
        let decoded = try JSONDecoder().decode(ItemStore.Saved.self, from: JSONEncoder().encode(saved))
        #expect(decoded == saved)
    }
}
