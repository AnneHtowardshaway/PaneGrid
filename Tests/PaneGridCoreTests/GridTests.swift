import XCTest
import CoreGraphics
@testable import PaneGridCore

final class GridTests: XCTestCase {
    let screen = CGRect(x: 0, y: 32, width: 1440, height: 840)

    func testEveryGridTileFitsAndDoesNotOverlap() throws {
        for columns in 1...24 {
            for rows in 1...24 {
                let grid = GridSize(columns: columns, rows: rows)
                for row in 0..<rows {
                    for column in 0..<columns {
                        let frame = try GridGeometry.frame(for: .init(column: column, row: row), grid: grid,
                                                           visibleFrame: screen, gap: 8, margin: 8, scale: 2)
                        XCTAssertTrue(screen.contains(frame))
                        XCTAssertGreaterThan(frame.width, 0)
                        XCTAssertGreaterThan(frame.height, 0)
                        if column + 1 < columns {
                            let next = try GridGeometry.frame(for: .init(column: column + 1, row: row), grid: grid,
                                                              visibleFrame: screen, gap: 8, margin: 8, scale: 2)
                            XCTAssertEqual(next.minX - frame.maxX, 8, accuracy: 0.001)
                        }
                    }
                }
            }
        }
    }

    func testSixthsAndEighthsCoverDisplayWithNoGap() throws {
        for grid in [GridSize(columns: 3, rows: 2), GridSize(columns: 4, rows: 2)] {
            var area = 0.0
            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    let frame = try GridGeometry.frame(for: .init(column: column, row: row), grid: grid,
                                                       visibleFrame: screen, gap: 0, margin: 0)
                    area += frame.width * frame.height
                }
            }
            XCTAssertEqual(area, screen.width * screen.height)
        }
    }

    func testSpanningSelectionIncludesInteriorGaps() throws {
        let grid = GridSize(columns: 4, rows: 6)
        let full = try GridGeometry.frame(for: .init(column: 0, row: 0, columnSpan: 4, rowSpan: 6),
                                         grid: grid, visibleFrame: screen, gap: 8, margin: 8)
        XCTAssertEqual(full, screen.insetBy(dx: 8, dy: 8))
        XCTAssertEqual(GridRegion.spanning((3, 5), (1, 2)), .init(column: 1, row: 2, columnSpan: 3, rowSpan: 4))
    }

    func testNegativeAndVerticalMonitorCoordinatesRoundTrip() {
        for rect in [CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                     CGRect(x: 100, y: 1080, width: 900, height: 1500)] {
            let converted = GridGeometry.flip(rect, primaryHeight: 1080)
            XCTAssertEqual(GridGeometry.flip(converted, primaryHeight: 1080), rect)
        }
        XCTAssertEqual(GridGeometry.flip(CGRect(x: 0, y: 0, width: 100, height: 100), primaryHeight: 900).minY, 800)
    }

    func testInvalidAndExtremeRegionsAreRejectedWithoutOverflow() {
        let grid = GridSize(columns: 4, rows: 4)
        for region in [GridRegion(column: -1, row: 0), .init(column: Int.max, row: 0),
                       .init(column: 1, row: 1, columnSpan: Int.max), .init(column: 0, row: 0, rowSpan: 0)] {
            XCTAssertFalse(region.isValid(in: grid))
            XCTAssertThrowsError(try GridGeometry.frame(for: region, grid: grid, visibleFrame: screen, gap: 8, margin: 8))
        }
        XCTAssertThrowsError(try GridGeometry.frame(for: .init(column: 0, row: 0), grid: grid,
                                                   visibleFrame: screen, gap: .nan, margin: 8))
        XCTAssertThrowsError(try GridGeometry.frame(for: .init(column: 0, row: 0), grid: grid,
                                                   visibleFrame: .zero, gap: 8, margin: 8))
    }

    func testMarginsCannotConsumeTheDisplay() {
        XCTAssertThrowsError(try GridGeometry.frame(for: .init(column: 0, row: 0), grid: .init(columns: 1, rows: 1),
                                                   visibleFrame: CGRect(x: 0, y: 0, width: 80, height: 80), gap: 0, margin: 64))
    }

    func testReservedOnlyPlanDoesNotInventWindows() throws {
        let reserved = Placement(windowID: "only", region: .init(column: 3, row: 3))
        let plan = try LayoutPlanner.pack(windowIDs: [], grid: .init(columns: 4, rows: 4), reserved: [reserved])
        XCTAssertEqual(plan.placements, [reserved])
        XCTAssertTrue(plan.overflow.isEmpty)
    }

    func testPanelStaysInsideSecondaryScreen() {
        let visible = CGRect(x: -1920, y: 0, width: 1920, height: 1040)
        let clamped = GridGeometry.clampPanel(CGRect(x: -100, y: -50, width: 380, height: 430), to: visible)
        XCTAssertTrue(visible.insetBy(dx: 8, dy: 8).contains(clamped))
    }

    func testPackingReservesSpansAndLeavesUnfilledCellsEmpty() throws {
        let grid = GridSize(columns: 4, rows: 4)
        let first = Placement(windowID: "main", region: .init(column: 0, row: 0, columnSpan: 2, rowSpan: 2))
        let plan = try LayoutPlanner.pack(windowIDs: ["main", "a", "b", "a"], grid: grid, reserved: [first])
        XCTAssertEqual(plan.placements.count, 3)
        XCTAssertEqual(plan.placements[1].region, .init(column: 2, row: 0))
        XCTAssertEqual(plan.placements[2].region, .init(column: 3, row: 0))
        XCTAssertTrue(plan.overflow.isEmpty)
    }

    func testPackingReportsOverflowWithoutMovingExtraWindows() throws {
        let plan = try LayoutPlanner.pack(windowIDs: ["a", "b", "c"], grid: .init(columns: 2, rows: 1))
        XCTAssertEqual(plan.placements.map(\.windowID), ["a", "b"])
        XCTAssertEqual(plan.overflow, ["c"])
    }

    func testPackingRejectsOverlapsAndDuplicateReservedWindows() {
        let grid = GridSize(columns: 4, rows: 4)
        let a = Placement(windowID: "a", region: .init(column: 0, row: 0, columnSpan: 2))
        let b = Placement(windowID: "b", region: .init(column: 1, row: 0))
        XCTAssertThrowsError(try LayoutPlanner.pack(windowIDs: [], grid: grid, reserved: [a, b]))
        XCTAssertThrowsError(try LayoutPlanner.pack(windowIDs: [], grid: grid, reserved: [a, a]))
    }
}

final class ConfigurationTests: XCTestCase {
    func testVersionOneSettingsMigrateWithoutLosingGridOrLayouts() throws {
        var config = Configuration()
        config.settings.grid = .init(columns: 3, rows: 2)
        config.settings.reflowSelection = true
        config.layouts = [.init(name: "Existing", grid: config.settings.grid, slots: [])]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: config.encoded()) as? [String: Any])
        var settings = try XCTUnwrap(json["settings"] as? [String: Any])
        settings.removeValue(forKey: "tileAllAppWindows")
        settings.removeValue(forKey: "autoFitAppWindows")
        json["settings"] = settings
        let migrated = try Configuration.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated, config)
        XCTAssertFalse(migrated.settings.tileAllAppWindows)
        XCTAssertTrue(migrated.settings.autoFitAppWindows)
        var toggled = migrated
        toggled.settings.tileAllAppWindows = true
        toggled.settings.autoFitAppWindows = false
        XCTAssertEqual(try Configuration.decode(toggled.encoded()), toggled)
    }

    func testRoundTripPreservesCustomSettingsAndEmptyCells() throws {
        var config = Configuration()
        config.settings.grid = .init(columns: 6, rows: 6)
        config.settings.requireOption = true
        config.layouts = [.init(name: "Focus", grid: config.settings.grid, slots: [
            .init(region: .init(column: 0, row: 0, columnSpan: 3, rowSpan: 4),
                  window: .init(bundleID: "example.editor", title: "Notes"))
        ])]
        XCTAssertEqual(try Configuration.decode(config.encoded()), config)
        XCTAssertEqual(config.layouts[0].slots.count, 1)
    }

    func testRejectsUnknownVersionAndMalformedSettings() throws {
        var config = Configuration()
        config.schemaVersion = 99
        XCTAssertThrowsError(try config.encoded())
        config.schemaVersion = 1
        config.settings.gap = -1
        XCTAssertThrowsError(try config.encoded())
        config.settings.gap = 8
        config.settings.hoverDelay = 0
        XCTAssertThrowsError(try config.encoded())
        XCTAssertThrowsError(try Configuration.decode(Data(repeating: 32, count: 2_000_001)))
    }

    func testCorruptGridJSONIsRejectedNotSilentlyClamped() {
        XCTAssertThrowsError(try JSONDecoder().decode(GridSize.self, from: Data("{\"columns\":0,\"rows\":999}".utf8)))
    }

    func testSavedLayoutRejectsDuplicateWindowsAndOverlaps() {
        let identity = WindowIdentity(bundleID: "example.app", title: "One")
        let a = SavedSlot(region: .init(column: 0, row: 0), window: identity)
        let b = SavedSlot(region: .init(column: 1, row: 0), window: identity)
        XCTAssertThrowsError(try SavedLayout(name: "Bad", grid: .init(columns: 4, rows: 4), slots: [a, b]).validate())
    }

    func testDifferentOrdinalsDoNotDisambiguateIdenticallyTitledWindows() {
        let first = WindowIdentity(bundleID: "example.app", title: "Untitled", ordinal: 0)
        let second = WindowIdentity(bundleID: "example.app", title: "Untitled", ordinal: 1)
        XCTAssertNil(SavedWindowMatcher.match(first, candidates: [("a", first), ("b", second)]))
        XCTAssertNil(SavedWindowMatcher.match(first, candidates: [("a", first), ("b", second)], excluding: ["b"]))
        let slot = SavedSlot(region: .init(column: 0, row: 0), window: second)
        XCTAssertThrowsError(try SavedLayout(name: "Ambiguous", grid: .init(columns: 2, rows: 2), slots: [slot]).validate())
    }

    func testMissingAndAmbiguousWindowsRemainEmpty() {
        let identity = WindowIdentity(bundleID: "example.app", title: "One")
        XCTAssertNil(SavedWindowMatcher.match(identity, candidates: []))
        XCTAssertNil(SavedWindowMatcher.match(identity, candidates: [("a", identity), ("b", identity)]))
        XCTAssertNil(SavedWindowMatcher.match(identity, candidates: [("a", .init(bundleID: "other", title: "One"))]))
        XCTAssertEqual(SavedWindowMatcher.match(identity, candidates: [("a", identity)]), "a")
        XCTAssertNil(SavedWindowMatcher.match(identity, candidates: [("a", identity)], excluding: ["a"]))
    }
}
