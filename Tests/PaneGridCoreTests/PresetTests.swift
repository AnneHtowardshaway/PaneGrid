import XCTest
@testable import PaneGridCore

final class PresetTests: XCTestCase {
    func testPresetsAreUniqueBoundedAndFitThreePickerRows() {
        let presets = GridSize.presets
        XCTAssertFalse(presets.isEmpty)
        XCTAssertEqual(Set(presets).count, presets.count)
        XCTAssertLessThanOrEqual(presets.count, 5 * 3)
        for grid in presets {
            XCTAssertTrue((1...GridSize.limit).contains(grid.columns), grid.label)
            XCTAssertTrue((1...GridSize.limit).contains(grid.rows), grid.label)
        }
    }

    func testCommonDimensionsAppearFirstInDimensionOrder() {
        let common: [GridSize] = [
            .init(columns: 2, rows: 1), .init(columns: 2, rows: 2),
            .init(columns: 3, rows: 1), .init(columns: 3, rows: 2),
            .init(columns: 3, rows: 3), .init(columns: 4, rows: 2),
            .init(columns: 4, rows: 3), .init(columns: 4, rows: 4)
        ]
        XCTAssertEqual(Array(GridSize.presets.prefix(common.count)), common)
    }

    func testLargePresetsRemainAvailableThrough24By24() {
        let large: [GridSize] = [
            .init(columns: 4, rows: 6), .init(columns: 6, rows: 4),
            .init(columns: 6, rows: 6), .init(columns: 8, rows: 8),
            .init(columns: 12, rows: 12), .init(columns: 24, rows: 24)
        ]
        XCTAssertEqual(Array(GridSize.presets.dropFirst(8)), large)
    }
}
