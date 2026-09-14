import SwiftUI
import PaneGridCore

struct QuickPickerView: View {
    @ObservedObject var state: AppState
    let window: LiveWindow
    let preview: (GridRegion?) -> Void
    let close: () -> Void
    @State private var region = GridRegion(column: 0, row: 0)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PaneMark().scaleEffect(0.8).frame(width: 29, height: 29)
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.app.name).font(.system(size: 14, weight: .semibold))
                    Text(window.displayTitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Close picker")
            }
            Picker("Display", selection: $state.displayID) {
                ForEach(state.displays) { display in Text(display.name).tag(display.id) }
            }.controlSize(.small)
            Toggle("Tile all windows of this app", isOn: $state.settings.tileAllAppWindows)
                .font(.system(size: 12, weight: .semibold)).toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("picker.tile-all-app")
                .help("Applies to \(window.app.name) only. Choose a preset to tile immediately; other apps stay unchanged.")
            PresetStrip(state: state, compact: true, onSelect: { grid in
                if state.settings.tileAllAppWindows { state.tileApplication(window, requestedGrid: grid) }
            })
            if let feedback = state.appTileFeedback,
               feedback.request.target.app.pid == window.app.pid {
                VStack(alignment: .leading, spacing: 7) {
                    Label("\(feedback.request.grid.label) was not applied", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(feedback.message).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true).help(feedback.message)
                    if let grid = feedback.suggestedGrid {
                        Button("Try \(grid.label) instead") { state.useSuggestedGrid(for: feedback.request.target) }
                            .controlSize(.small).accessibilityIdentifier("picker.accept-suggested-grid")
                    }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("picker.arrangement-failure")
            }
            GridDimensions(state: state, compact: true)
            GridCanvas(grid: state.settings.grid, selection: $region,
                       onCommit: { state.snap(window, to: $0) }, onPreview: preview)
                .frame(height: 194).accessibilityIdentifier("picker.grid")
            HStack {
                Text(state.settings.tileAllAppWindows ? "Preset: tile all · Drag: same size for all" : "Drag to span · Release to resize")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(region.columnSpan) × \(region.rowSpan)").font(.caption.monospacedDigit()).foregroundStyle(PaneStyle.accent)
            }
            HStack {
                if state.settings.tileAllAppWindows {
                    Button("Tile app windows") { state.tileApplication(window) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("picker.tile-app-now")
                } else {
                    Button("Fill") { state.snap(window, to: .init(column: 0, row: 0, columnSpan: state.settings.grid.columns, rowSpan: state.settings.grid.rows)) }
                    Button("Center") { state.center(window) }
                }
                Button("Undo") { state.undo() }.disabled(state.undoDepth == 0)
                Spacer()
                Button("Workspace…") { close(); state.onShowWorkspace?() }
            }.controlSize(.small)
            Divider()
            if state.settings.tileAllAppWindows {
                Toggle("Suggest a fitting grid if needed", isOn: $state.settings.autoFitAppWindows)
                    .font(.caption).toggleStyle(.checkbox).accessibilityIdentifier("picker.auto-fit-app")
                Text("\(window.app.name) only. Presets never change automatically.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Toggle("Reflow my selected group (\(state.selectedIDs.count))", isOn: $state.settings.reflowSelection)
                    .font(.caption).toggleStyle(.checkbox)
            }
            Text("Blank cells stay empty. Esc closes. Shift + arrows changes the span.")
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.1), lineWidth: 1))
        .tint(PaneStyle.accent).preferredColorScheme(state.colorScheme)
        .disabled(state.isBusy || state.isPaused)
    }
}
