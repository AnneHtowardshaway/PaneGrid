import Foundation
import CoreGraphics

public enum EqualTileError: Error, LocalizedError, Equatable {
    case insufficientCells(windows: Int, capacity: Int)
    public var errorDescription: String? {
        switch self {
        case .insufficientCells(let count, let capacity):
            return "This portion has room for \(capacity) windows, but the app has \(count). Choose smaller portions or a grid with more cells. Nothing was moved."
        }
    }
}

public enum EqualTilePlanner {
    /// Fill row-major, equal-sized portions. Never silently resize just a prefix of the app's windows.
    public static func plan(windowIDs: [String], grid: GridSize, columnSpan: Int = 1, rowSpan: Int = 1) throws -> [Placement] {
        let tile = GridRegion(column: 0, row: 0, columnSpan: columnSpan, rowSpan: rowSpan)
        guard tile.isValid(in: grid) else { throw GridError.invalidRegion }
        guard Set(windowIDs).count == windowIDs.count else { throw GridError.duplicateWindow }
        let columns = grid.columns / columnSpan
        let rows = grid.rows / rowSpan
        guard windowIDs.count <= columns * rows else {
            throw EqualTileError.insufficientCells(windows: windowIDs.count, capacity: columns * rows)
        }
        return windowIDs.enumerated().map { index, id in
            .init(windowID: id, region: .init(column: (index % columns) * columnSpan, row: (index / columns) * rowSpan,
                                            columnSpan: columnSpan, rowSpan: rowSpan))
        }
    }

    /// Try an equally divided screen, with at least as much area per tile as requested.
    /// The row/column balance may change (e.g. 3×2 → 2×3 for wide, short windows).
    public static func fittingGrid(windowCount: Int, requested: GridSize, minimum: CGSize,
                                   visibleFrame: CGRect, gap: Double, margin: Double, scale: Double) -> GridSize? {
        guard windowCount > 0, windowCount <= requested.count,
              minimum.width.isFinite, minimum.height.isFinite, minimum.width >= 0, minimum.height >= 0 else { return nil }
        var candidates: [GridSize] = []
        for columns in 1...GridSize.limit {
            for rows in 1...GridSize.limit {
                let grid = GridSize(columns: columns, rows: rows)
                guard grid.count >= windowCount, grid.count <= requested.count,
                      let cell = try? GridGeometry.frame(for: .init(column: 0, row: 0), grid: grid,
                                                         visibleFrame: visibleFrame, gap: gap, margin: margin, scale: scale),
                      cell.width + FrameSettler.tolerance >= minimum.width,
                      cell.height + FrameSettler.tolerance >= minimum.height else { continue }
                candidates.append(grid)
            }
        }
        return candidates.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            let aDistance = abs(a.columns - requested.columns) + abs(a.rows - requested.rows)
            let bDistance = abs(b.columns - requested.columns) + abs(b.rows - requested.rows)
            if aDistance != bDistance { return aDistance < bDistance }
            return a.columns > b.columns
        }.first
    }
}
