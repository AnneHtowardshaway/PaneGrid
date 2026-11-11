import Foundation
import CoreGraphics
import PaneGridCore

struct TilingSurface: Sendable {
    let visibleFrame: CGRect
    let gap: Double
    let margin: Double
    let scale: Double

    func frame(_ region: GridRegion, grid: GridSize) throws -> CGRect {
        try GridGeometry.frame(for: region, grid: grid, visibleFrame: visibleFrame, gap: gap, margin: margin, scale: scale)
    }
}

struct ApplicationTileResult: Sendable {
    let report: MoveReport
    let usedGrid: GridSize
    let adapted: Bool
    var suggestedGrid: GridSize? = nil
}

enum ApplicationTiler {
    static func tile(target: LiveWindow, access: WindowAccess, grid: GridSize, columnSpan: Int = 1, rowSpan: Int = 1,
                     surface: TilingSurface, autoFit: Bool) async -> ApplicationTileResult {
        do {
            let windows = try await access.applicationWindows(containing: target)
            // Validate capacity before touching any frame. This mode means ALL, never a silent subset.
            let plan = try EqualTilePlanner.plan(windowIDs: windows.map(\.id), grid: grid, columnSpan: columnSpan, rowSpan: rowSpan)
            let moves = try zip(windows, plan).map { window, placement in
                WindowMove(window: window, destination: try surface.frame(placement.region, grid: grid))
            }
            let report = await access.apply(moves)
            if report.succeeded {
                return .init(report: .init(succeeded: true,
                                            message: Localization.tf("Tiled all %ld eligible %@ windows using %@. Other apps were untouched.",
                                                                     windows.count, target.app.name, grid.label),
                                            movedCount: windows.count),
                             usedGrid: grid, adapted: false)
            }
            // A preset is a command, not a hint. Never apply a different grid behind the user's back.
            // The persisted auto-fit preference now controls suggestions, which require a NEW explicit command.
            var suggestion: GridSize?
            if autoFit, let failure = report.failure, failure.rollbackFailures == 0,
               let observed = failure.constrainedMinimum {
                let partitions = GridSize(columns: grid.columns / columnSpan, rows: grid.rows / rowSpan)
                let candidate = EqualTilePlanner.fittingGrid(windowCount: windows.count, requested: partitions, minimum: observed,
                                                             visibleFrame: surface.visibleFrame, gap: surface.gap, margin: surface.margin, scale: surface.scale)
                if candidate != partitions { suggestion = candidate }
            }
            return .init(report: .init(succeeded: false,
                                      message: Localization.tf("%@ was not applied. %@ Your chosen grid has not been changed.", grid.label, report.message),
                                      movedCount: 0, failure: report.failure), usedGrid: grid, adapted: false, suggestedGrid: suggestion)
        } catch {
            return .init(report: .init(succeeded: false, message: error.localizedDescription, movedCount: 0), usedGrid: grid, adapted: false)
        }
    }
}
