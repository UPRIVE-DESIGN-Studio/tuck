import CoreGraphics
import Testing
@testable import Tuck

/// The usable area of a 14" MacBook Pro: 1512 × 982 points, less a 37 point menu bar.
struct ZoneLayoutTests {
    let laptop = ZoneLayout(area: CGRect(x: 0, y: 0, width: 1512, height: 945))

    @Test func gridFollowsTheDisplayShape() {
        #expect((laptop.columns, laptop.rows) == (2, 2))
        let ultrawide = ZoneLayout(area: CGRect(x: 0, y: 0, width: 3440, height: 1410))
        #expect((ultrawide.columns, ultrawide.rows) == (3, 1))
        let portrait = ZoneLayout(area: CGRect(x: 0, y: 0, width: 1080, height: 1890))
        #expect((portrait.columns, portrait.rows) == (1, 2))
    }

    @Test func cellInteriorTargetsAQuarter() {
        // Cocoa coordinates: a high y is near the top.
        #expect(laptop.target(for: CGPoint(x: 300, y: 700)) == CGRect(x: 0, y: 473, width: 756, height: 472))
        #expect(laptop.target(for: CGPoint(x: 1200, y: 200)) == CGRect(x: 756, y: 0, width: 756, height: 473))
    }

    @Test func horizontalDividerSpansTheColumn() {
        #expect(laptop.target(for: CGPoint(x: 300, y: 480)) == CGRect(x: 0, y: 0, width: 756, height: 945))
    }

    @Test func verticalDividerSpansTheRow() {
        #expect(laptop.target(for: CGPoint(x: 760, y: 800)) == CGRect(x: 0, y: 473, width: 1512, height: 472))
    }

    @Test func centreAndTopEdgeFillTheArea() {
        #expect(laptop.target(for: CGPoint(x: 756, y: 472)) == laptop.area)
        #expect(laptop.target(for: CGPoint(x: 100, y: 940)) == laptop.area)
        // The menu bar, above the usable area.
        #expect(laptop.target(for: CGPoint(x: 100, y: 960)) == laptop.area)
    }

    @Test func offTheAreaTargetsNothing() {
        let right = ZoneLayout(area: CGRect(x: 1512, y: 0, width: 1920, height: 1050))
        #expect(right.target(for: CGPoint(x: 300, y: 500)) == nil)
    }

    @Test func fixedSizeWindowIsCentredOnlyWhereItFits() {
        let zone = CGRect(x: 0, y: 0, width: 756, height: 472)
        #expect(ZoneLayout.dropFrame(in: zone, windowSize: CGSize(width: 400, height: 300), resizable: false)
            == CGRect(x: 178, y: 86, width: 400, height: 300))
        #expect(ZoneLayout.dropFrame(in: zone, windowSize: CGSize(width: 800, height: 300), resizable: false) == nil)
        #expect(ZoneLayout.dropFrame(in: zone, windowSize: CGSize(width: 800, height: 300), resizable: true) == zone)
    }
}
