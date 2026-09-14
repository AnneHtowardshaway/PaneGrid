import XCTest
import CoreGraphics
@testable import PaneGridCore

final class EqualTilePlannerTests: XCTestCase {
    let visible = CGRect(x: 0, y: 30, width: 2560, height: 1410)

    func testAppWindowsEachReceiveOneEqualPortionWithoutSelection() throws {
        let ids = (0..<6).map { "window-\($0)" }
        let placements = try EqualTilePlanner.plan(windowIDs: ids, grid: .init(columns: 3, rows: 2))
        XCTAssertEqual(placements.map(\.windowID), ids)
        XCTAssertEqual(Set(placements.map(\.region)).count, 6)
        XCTAssertEqual(placements.last?.region, .init(column: 2, row: 1))
    }

    func testIdenticalSpansAndEmptySpace() throws {
        let plan = try EqualTilePlanner.plan(windowIDs: ["a", "b", "c"], grid: .init(columns: 4, rows: 4), columnSpan: 2, rowSpan: 2)
        XCTAssertEqual(plan.map(\.region), [.init(column: 0, row: 0, columnSpan: 2, rowSpan: 2),
                                           .init(column: 2, row: 0, columnSpan: 2, rowSpan: 2),
                                           .init(column: 0, row: 2, columnSpan: 2, rowSpan: 2)])
    }

    func testOverflowIsNotAPartialArrangement() {
        XCTAssertThrowsError(try EqualTilePlanner.plan(windowIDs: ["a", "b", "c"], grid: .init(columns: 2, rows: 1))) {
            XCTAssertEqual($0 as? EqualTileError, .insufficientCells(windows: 3, capacity: 2))
        }
        XCTAssertThrowsError(try EqualTilePlanner.plan(windowIDs: ["a", "a"], grid: .init(columns: 4, rows: 4)))
    }

    func testEveryValidSpanLeavesNonOverlappingEqualTiles() throws {
        for columns in 1...24 {
            for rows in 1...24 {
                let grid = GridSize(columns: columns, rows: rows)
                let width = max(1, columns / 3), height = max(1, rows / 2)
                let count = (columns / width) * (rows / height)
                let plan = try EqualTilePlanner.plan(windowIDs: (0..<count).map(String.init), grid: grid, columnSpan: width, rowSpan: height)
                for (index, entry) in plan.enumerated() {
                    XCTAssertTrue(entry.region.isValid(in: grid))
                    XCTAssertEqual(entry.region.columnSpan, width)
                    XCTAssertEqual(entry.region.rowSpan, height)
                    XCTAssertFalse(plan.prefix(index).contains { $0.region.intersects(entry.region) })
                }
            }
        }
    }

    func testMeasuredMinimumCanRebalanceRowsWithoutDroppingWindows() {
        let grid = EqualTilePlanner.fittingGrid(windowCount: 6, requested: .init(columns: 3, rows: 2), minimum: .init(width: 1000, height: 0),
                                                visibleFrame: visible, gap: 8, margin: 8, scale: 2)
        XCTAssertEqual(grid, .init(columns: 2, rows: 3))
    }

    func testDenseGridCoarsensToFitAndImpossibleGroupDoesNotOverflow() {
        let fit = EqualTilePlanner.fittingGrid(windowCount: 4, requested: .init(columns: 6, rows: 6), minimum: .init(width: 1000, height: 600),
                                               visibleFrame: visible, gap: 8, margin: 8, scale: 2)
        XCTAssertEqual(fit, .init(columns: 2, rows: 2))
        XCTAssertNil(EqualTilePlanner.fittingGrid(windowCount: 6, requested: .init(columns: 6, rows: 6), minimum: .init(width: 1000, height: 600),
                                                  visibleFrame: visible, gap: 8, margin: 8, scale: 2))
    }
}
