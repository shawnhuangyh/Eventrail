import SwiftUI
import Testing
@testable import Eventrail

/// The iPhone Duo's fold parts a screen only where it runs from one edge of
/// it to the other and leaves a half worth laying out on either side — the
/// inner screen opened on its side (951 × 669 points) or turned upright
/// (669 × 951), the crease and its margins a 40-point strip down the middle —
/// and an iPad is parted down its middle where it is held on its side.
struct FoldTests {
    static let open = CGRect(x: 0, y: 0, width: 879, height: 669)
    static let turned = CGRect(x: 0, y: 0, width: 669, height: 951)

    @Test func aFoldRunningTopToBottomPutsTheHalvesSideBySide() throws {
        let fold = try #require(Fold(CGRect(x: 455, y: -20, width: 40, height: 709), in: Self.open))
        #expect(fold.axis == .vertical)
        #expect(fold.frame.minX == 455)
    }

    @Test func aFoldRunningAcrossStacksTheHalves() throws {
        let fold = try #require(Fold(CGRect(x: 0, y: 455, width: 669, height: 40), in: Self.turned))
        #expect(fold.axis == .horizontal)
    }

    /// A region reported only as far as the view it crosses still crosses it.
    @Test func aFoldClippedToTheViewStillCrossesIt() {
        #expect(Fold(CGRect(x: 455, y: 0, width: 40, height: 669), in: Self.open)?.axis == .vertical)
    }

    /// A sheet or a popover the fold runs through off centre is left whole:
    /// a sliver on one side of it is no half.
    @Test func aFoldLeavingAHalfTooNarrowPartsNothing() {
        #expect(Fold(CGRect(x: 120, y: 0, width: 40, height: 669), in: Self.open) == nil)
        #expect(Fold(CGRect(x: 760, y: 0, width: 40, height: 669), in: Self.open) == nil)
        #expect(Fold(CGRect(x: 0, y: 100, width: 669, height: 40), in: Self.turned) == nil)
    }

    /// A view that ends short of the crease's length — a card, not a screen —
    /// is not parted by it.
    @Test func aFoldThatStopsShortOfAnEdgePartsNothing() {
        #expect(Fold(CGRect(x: 455, y: 0, width: 40, height: 500), in: Self.open) == nil)
        #expect(Fold(CGRect(x: 100, y: 455, width: 400, height: 40), in: Self.turned) == nil)
    }

    /// An iPad on its side is parted down its middle, with no strip between
    /// the halves: an iPad Air 11-inch's screen under its bars, and an iPad
    /// mini's, the narrowest held that way.
    @Test func anIPadOnItsSideIsPartedDownTheMiddle() throws {
        let air = try #require(Fold(parting: CGSize(width: 1180, height: 726)))
        #expect(air.axis == .vertical)
        #expect(air.frame == CGRect(x: 590, y: 0, width: 0, height: 726))
        #expect(Fold(parting: CGSize(width: 1133, height: 650))?.frame.minX == 566.5)
    }

    /// Upright, an iPad stays whole, and so does a window — or a sheet —
    /// too narrow for two halves of a phone's width, however wide its shape.
    @Test func anIPadUprightOrANarrowWindowIsNotParted() {
        #expect(Fold(parting: CGSize(width: 820, height: 1080)) == nil)
        #expect(Fold(parting: CGSize(width: 700, height: 500)) == nil)
        #expect(Fold(parting: CGSize(width: 750, height: 600)) != nil)
    }

    /// A Mac's window keeps a list's width before the event beside it, however
    /// wide it is pulled, and stays whole where that leaves too little room
    /// for the event — whatever its shape, since a Mac's window is not turned.
    @Test func aMacWindowKeepsAListsWidthBeforeTheEvent() throws {
        let window = try #require(Fold(listBeside: CGSize(width: 1440, height: 848)))
        #expect(window.axis == .vertical)
        #expect(window.frame == CGRect(x: Fold.macListWidth, y: 0, width: 0, height: 848))
        #expect(Fold(listBeside: CGSize(width: 2400, height: 1300))?.frame.minX == Fold.macListWidth)
        #expect(Fold(listBeside: CGSize(width: 900, height: 1000)) == nil)
        #expect(Fold(listBeside: CGSize(width: Fold.macListWidth + Fold.leastMacPane, height: 1000)) != nil)
    }
}
