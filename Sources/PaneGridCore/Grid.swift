import Foundation
import CoreGraphics

public struct GridSize: Codable, Hashable, Sendable {
    public static let limit = 24
    public let columns: Int
    public let rows: Int
    public var count: Int { columns * rows }
    public var label: String { "\(columns) × \(rows)" }

    public init(columns: Int, rows: Int) {
        self.columns = min(Self.limit, max(1, columns))
        self.rows = min(Self.limit, max(1, rows))
    }

    private enum CodingKeys: String, CodingKey { case columns, rows }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let columns = try values.decode(Int.self, forKey: .columns)
        let rows = try values.decode(Int.self, forKey: .rows)
        guard (1...Self.limit).contains(columns), (1...Self.limit).contains(rows) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Grid dimensions must be between 1 and 24."))
        }
        self.init(columns: columns, rows: rows)
    }

    public static let presets: [GridSize] = [
        .init(columns: 2, rows: 1), .init(columns: 2, rows: 2),
        .init(columns: 3, rows: 1), .init(columns: 3, rows: 2),
        .init(columns: 3, rows: 3), .init(columns: 4, rows: 2),
        .init(columns: 4, rows: 3), .init(columns: 4, rows: 4),
        .init(columns: 4, rows: 6), .init(columns: 6, rows: 4),
        .init(columns: 6, rows: 6), .init(columns: 8, rows: 8),
        .init(columns: 12, rows: 12), .init(columns: 24, rows: 24)
    ]
}

public struct GridRegion: Codable, Hashable, Sendable {
    public var column: Int
    public var row: Int
    public var columnSpan: Int
    public var rowSpan: Int

    public init(column: Int, row: Int, columnSpan: Int = 1, rowSpan: Int = 1) {
        self.column = column
        self.row = row
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
    }

    public func isValid(in grid: GridSize) -> Bool {
        column >= 0 && row >= 0 && column < grid.columns && row < grid.rows &&
        columnSpan > 0 && rowSpan > 0 &&
        columnSpan <= grid.columns - column && rowSpan <= grid.rows - row
    }

    public func contains(column: Int, row: Int) -> Bool {
        guard isValid(in: .init(columns: 24, rows: 24)) else { return false }
        return column >= self.column && column < self.column + columnSpan &&
               row >= self.row && row < self.row + rowSpan
    }

    public func intersects(_ other: GridRegion) -> Bool {
        guard isValid(in: .init(columns: 24, rows: 24)),
              other.isValid(in: .init(columns: 24, rows: 24)) else { return false }
        return column < other.column + other.columnSpan && other.column < column + columnSpan &&
               row < other.row + other.rowSpan && other.row < row + rowSpan
    }

    public static func spanning(_ start: (column: Int, row: Int), _ end: (column: Int, row: Int)) -> GridRegion {
        .init(column: min(start.column, end.column), row: min(start.row, end.row),
              columnSpan: abs(end.column - start.column) + 1,
              rowSpan: abs(end.row - start.row) + 1)
    }
}

public enum GridError: Error, LocalizedError, Equatable {
    case invalidRegion, invalidScreen, overlappingRegions, duplicateWindow, invalidConfiguration
    public var errorDescription: String? {
        switch self {
        case .invalidRegion: return "A tile is outside the grid. Choose a new region."
        case .invalidScreen: return "The display has no usable space for this grid."
        case .overlappingRegions: return "Two assignments overlap. Clear one of them first."
        case .duplicateWindow: return "A window can only be assigned once."
        case .invalidConfiguration: return "This layout file is invalid or uses an unsupported version."
        }
    }
}

public enum GridGeometry {
    /// All rectangles here are in Accessibility/Quartz coordinates: origin at primary display's top left.
    public static func frame(for region: GridRegion, grid: GridSize, visibleFrame: CGRect,
                             gap: Double, margin: Double, scale: Double = 1) throws -> CGRect {
        guard region.isValid(in: grid) else { throw GridError.invalidRegion }
        guard [visibleFrame.minX, visibleFrame.minY, visibleFrame.width, visibleFrame.height,
               gap, margin, scale].allSatisfy({ $0.isFinite }),
              visibleFrame.size.width > 0, visibleFrame.size.height > 0, gap >= 0, margin >= 0,
              visibleFrame.width > 2 * margin, visibleFrame.height > 2 * margin,
              (1...4).contains(scale) else { throw GridError.invalidScreen }
        let area = visibleFrame.insetBy(dx: margin, dy: margin)
        let cellWidth = (area.width - Double(grid.columns - 1) * gap) / Double(grid.columns)
        let cellHeight = (area.height - Double(grid.rows - 1) * gap) / Double(grid.rows)
        guard cellWidth >= 1, cellHeight >= 1 else { throw GridError.invalidScreen }
        func pixel(_ value: Double) -> Double { (value * scale).rounded() / scale }
        let left = pixel(area.minX + Double(region.column) * (cellWidth + gap))
        let top = pixel(area.minY + Double(region.row) * (cellHeight + gap))
        let right = pixel(area.minX + Double(region.column + region.columnSpan) * (cellWidth + gap) - gap)
        let bottom = pixel(area.minY + Double(region.row + region.rowSpan) * (cellHeight + gap) - gap)
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Cocoa screen geometry uses bottom-left coordinates. This also handles negative display origins.
    public static func flip(_ rect: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func clampPanel(_ rect: CGRect, to visibleFrame: CGRect, inset: Double = 8) -> CGRect {
        let area = visibleFrame.insetBy(dx: inset, dy: inset)
        let width = min(rect.width, area.width)
        let height = min(rect.height, area.height)
        return CGRect(x: max(area.minX, min(rect.minX, area.maxX - width)),
                      y: max(area.minY, min(rect.minY, area.maxY - height)), width: width, height: height)
    }
}

public struct Placement: Equatable, Sendable {
    public var windowID: String
    public var region: GridRegion
    public init(windowID: String, region: GridRegion) { self.windowID = windowID; self.region = region }
}

public struct LayoutPlan: Equatable, Sendable {
    public var placements: [Placement]
    public var overflow: [String]
}

public enum LayoutPlanner {
    /// Preserve reserved spans and intentional holes; only pack the explicitly supplied windows.
    public static func pack(windowIDs: [String], grid: GridSize, reserved: [Placement] = []) throws -> LayoutPlan {
        var placements: [Placement] = []
        var seen = Set<String>()
        for entry in reserved {
            guard entry.region.isValid(in: grid) else { throw GridError.invalidRegion }
            guard seen.insert(entry.windowID).inserted else { throw GridError.duplicateWindow }
            guard !placements.contains(where: { $0.region.intersects(entry.region) }) else { throw GridError.overlappingRegions }
            placements.append(entry)
        }
        var overflow: [String] = []
        for id in windowIDs where seen.insert(id).inserted {
            var destination: GridRegion?
            for row in 0..<grid.rows {
                for column in 0..<grid.columns {
                    let candidate = GridRegion(column: column, row: row)
                    if !placements.contains(where: { $0.region.intersects(candidate) }) { destination = candidate; break }
                }
                if destination != nil { break }
            }
            if let destination { placements.append(.init(windowID: id, region: destination)) }
            else { overflow.append(id) }
        }
        return LayoutPlan(placements: placements, overflow: overflow)
    }
}
