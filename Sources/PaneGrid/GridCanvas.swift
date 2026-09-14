import SwiftUI
import PaneGridCore

enum PaneStyle {
    static let accent = Color(red: 0.23, green: 0.72, blue: 0.62)
    static let violet = Color(red: 0.53, green: 0.48, blue: 0.9)
    static let colors: [Color] = [accent, violet, .cyan, .orange, .pink, .blue]
}

struct PaneMark: View {
    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4).fill(PaneStyle.accent)
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 4).fill(PaneStyle.violet)
                RoundedRectangle(cornerRadius: 4).fill(PaneStyle.accent.opacity(0.35))
            }
        }.frame(width: 33, height: 33).accessibilityHidden(true)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18)
            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.07), lineWidth: 1))
    }
}

struct TileLabel: Identifiable {
    let id: String
    let region: GridRegion
    let text: String
    let color: Color
}

struct GridCanvas: View {
    let grid: GridSize
    @Binding var selection: GridRegion
    var labels: [TileLabel] = []
    var onCommit: ((GridRegion) -> Void)?
    var onPreview: ((GridRegion?) -> Void)?
    @State private var dragStart: (column: Int, row: Int)?
    @State private var hover: GridRegion?
    @FocusState private var hasFocus: Bool

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let cellWidth = size.width / CGFloat(grid.columns)
                let cellHeight = size.height / CGFloat(grid.rows)
                func rect(_ region: GridRegion) -> CGRect {
                    CGRect(x: CGFloat(region.column) * cellWidth + 2,
                           y: CGFloat(region.row) * cellHeight + 2,
                           width: CGFloat(region.columnSpan) * cellWidth - 4,
                           height: CGFloat(region.rowSpan) * cellHeight - 4)
                }
                for row in 0..<grid.rows {
                    for column in 0..<grid.columns {
                        let cell = rect(.init(column: column, row: row))
                        let path = Path(roundedRect: cell, cornerRadius: min(6, cellWidth / 6))
                        context.fill(path, with: .color(.primary.opacity(0.045)))
                        context.stroke(path, with: .color(.primary.opacity(0.065)), lineWidth: 0.7)
                    }
                }
                for label in labels where label.region.isValid(in: grid) {
                    let frame = rect(label.region)
                    let path = Path(roundedRect: frame, cornerRadius: 6)
                    context.fill(path, with: .color(label.color.opacity(0.24)))
                    context.stroke(path, with: .color(label.color.opacity(0.65)), lineWidth: 1)
                    if frame.width > 32 && frame.height > 22 {
                        context.draw(Text(String(label.text.prefix(max(2, Int(frame.width / 7)))))
                            .font(.system(size: min(12, frame.height / 3), weight: .medium)).foregroundColor(.primary),
                                     at: CGPoint(x: frame.midX, y: frame.midY))
                    }
                }
                if selection.isValid(in: grid) {
                    let path = Path(roundedRect: rect(selection), cornerRadius: 6)
                    context.fill(path, with: .color(PaneStyle.accent.opacity(0.16)))
                    context.stroke(path, with: .color(PaneStyle.accent), lineWidth: 2.5)
                }
                if let hover, dragStart == nil, hover != selection {
                    context.stroke(Path(roundedRect: rect(hover), cornerRadius: 5), with: .color(PaneStyle.accent.opacity(0.65)), lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = cell(at: value.startLocation, size: geometry.size); hasFocus = true }
                    guard let dragStart else { return }
                    selection = GridRegion.spanning(dragStart, cell(at: value.location, size: geometry.size))
                    onPreview?(selection)
                }
                .onEnded { value in
                    let start = dragStart ?? cell(at: value.startLocation, size: geometry.size)
                    selection = GridRegion.spanning(start, cell(at: value.location, size: geometry.size))
                    dragStart = nil
                    onPreview?(nil)
                    onCommit?(selection)
                })
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let cell = cell(at: point, size: geometry.size)
                    hover = .init(column: cell.column, row: cell.row)
                    if dragStart == nil { onPreview?(hover) }
                case .ended:
                    hover = nil
                    if dragStart == nil { onPreview?(nil) }
                }
            }
        }
        .focusable()
        .focused($hasFocus)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            if press.key == .return { onCommit?(selection); return .handled }
            let dx = press.key == .rightArrow ? 1 : press.key == .leftArrow ? -1 : 0
            let dy = press.key == .downArrow ? 1 : press.key == .upArrow ? -1 : 0
            if press.modifiers.contains(.shift) {
                selection.columnSpan = min(grid.columns - selection.column, max(1, selection.columnSpan + dx))
                selection.rowSpan = min(grid.rows - selection.row, max(1, selection.rowSpan + dy))
            } else {
                selection.column = min(grid.columns - selection.columnSpan, max(0, selection.column + dx))
                selection.row = min(grid.rows - selection.rowSpan, max(0, selection.row + dy))
            }
            onPreview?(selection)
            return .handled
        }
        .onChange(of: grid) { _, _ in selection = .init(column: 0, row: 0); hover = nil; dragStart = nil; onPreview?(nil) }
        .accessibilityLabel("Window layout grid")
        .accessibilityValue("Column \(selection.column + 1), row \(selection.row + 1), spans \(selection.columnSpan) columns and \(selection.rowSpan) rows")
        .accessibilityHint("Arrow keys move the selection. Shift and arrows change its size. Return applies it.")
        .accessibilityChildren {
            ForEach(0..<grid.count, id: \.self) { index in
                Button("Column \(index % grid.columns + 1), row \(index / grid.columns + 1)") {
                    selection = .init(column: index % grid.columns, row: index / grid.columns)
                    onCommit?(selection)
                }
            }
        }
    }

    private func cell(at point: CGPoint, size: CGSize) -> (column: Int, row: Int) {
        let column = Int(max(0, min(Double(grid.columns - 1), Double(point.x / max(size.width, 1)) * Double(grid.columns))))
        let row = Int(max(0, min(Double(grid.rows - 1), Double(point.y / max(size.height, 1)) * Double(grid.rows))))
        return (column, row)
    }
}

struct GridDimensions: View {
    @ObservedObject var state: AppState
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 18) {
            dimension("Columns", value: state.settings.grid.columns) { state.setGrid(.init(columns: $0, rows: state.settings.grid.rows)) }
            Text("×").foregroundStyle(.tertiary)
            dimension("Rows", value: state.settings.grid.rows) { state.setGrid(.init(columns: state.settings.grid.columns, rows: $0)) }
            if !compact { Spacer(); Text("\(state.settings.grid.count) cells").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }

    private func dimension(_ label: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Stepper(value: Binding(get: { value }, set: set), in: 1...24) {
                Text("\(value)").font(.system(.body, design: .rounded, weight: .semibold)).monospacedDigit().frame(minWidth: 18)
            }.fixedSize().accessibilityLabel(label)
        }
    }
}

struct PresetStrip: View {
    @ObservedObject var state: AppState
    var compact = false
    var onSelect: ((GridSize) -> Void)?
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: compact ? 5 : 6),
                  alignment: .leading, spacing: 6) {
            ForEach(GridSize.presets, id: \.self) { grid in
                Button {
                    state.setGrid(grid)
                    onSelect?(grid)
                } label: {
                    Text(grid.label)
                        .font(.system(size: compact ? 11 : 12, weight: .medium)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .padding(.horizontal, compact ? 4 : 6).frame(maxWidth: .infinity)
                        .padding(.vertical, compact ? 6 : 7)
                        .foregroundStyle(state.settings.grid == grid ? PaneStyle.accent : .primary)
                        .background(state.settings.grid == grid ? PaneStyle.accent.opacity(0.15) : Color.primary.opacity(0.045), in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(grid.columns) columns, \(grid.rows) rows")
                    .accessibilityIdentifier("preset.\(grid.columns)x\(grid.rows)")
            }
        }
    }
}
