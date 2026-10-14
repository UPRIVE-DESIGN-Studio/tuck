import CoreGraphics
import Testing
@testable import Tuck

struct WindowSplitTests {
    /// Cocoa coordinates.
    let window = CGRect(x: 100, y: 100, width: 800, height: 600)

    @Test func leaningLeftTakesTheLeftHalf() {
        let split = WindowSplit.offer(window, at: CGPoint(x: 350, y: 420))
        #expect(split == WindowSplit(
            mine: CGRect(x: 100, y: 100, width: 400, height: 600),
            theirs: CGRect(x: 500, y: 100, width: 400, height: 600)
        ))
    }

    @Test func leaningRightTakesTheRightHalf() {
        #expect(WindowSplit.offer(window, at: CGPoint(x: 650, y: 380))?.mine == CGRect(x: 500, y: 100, width: 400, height: 600))
    }

    @Test func leaningUpStacksOnTop() {
        let split = WindowSplit.offer(window, at: CGPoint(x: 510, y: 530))
        #expect(split == WindowSplit(
            mine: CGRect(x: 100, y: 400, width: 800, height: 300),
            theirs: CGRect(x: 100, y: 100, width: 800, height: 300)
        ))
    }

    @Test func leaningDownStacksBelow() {
        #expect(WindowSplit.offer(window, at: CGPoint(x: 490, y: 270))?.mine == CGRect(x: 100, y: 100, width: 800, height: 300))
    }

    @Test func theWholeWindowOffersASplit() {
        #expect(WindowSplit.offer(window, at: CGPoint(x: 110, y: 400))?.mine == CGRect(x: 100, y: 100, width: 400, height: 600))
        #expect(WindowSplit.offer(window, at: CGPoint(x: 500, y: 690))?.mine == CGRect(x: 100, y: 400, width: 800, height: 300))
        #expect(WindowSplit.offer(window, at: CGPoint(x: 1000, y: 400)) == nil)
    }

    @Test func tooSmallToShareOffersNothing() {
        let narrow = CGRect(x: 0, y: 0, width: 400, height: 600)
        #expect(WindowSplit.offer(narrow, at: CGPoint(x: 120, y: 300)) == nil)
        // Still tall enough to stack.
        #expect(WindowSplit.offer(narrow, at: CGPoint(x: 200, y: 440))?.mine == CGRect(x: 0, y: 300, width: 400, height: 300))
    }
}
