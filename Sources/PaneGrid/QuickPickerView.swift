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
                    .buttonStyle(.plain).accessibilityLabel(Localization.t("Close picker"))
            }
            Picker(Localization.t("Display"), selection: $state.displayID) {
                ForEach(state.displays) { display in Text(display.name).tag(display.id) }
            }.controlSize(.small)
            Toggle(Localization.t("Tile all windows of this app"), isOn: $state.settings.tileAllAppWindows)
                .font(.system(size: 12, weight: .semibold)).toggleStyle(.switch).controlSize(.small)
                .accessibilityIdentifier("picker.tile-all-app")
                .help(Localization.tf("Applies to %@ only. Choose a preset to tile immediately; other apps stay unchanged.", window.app.name))
            PresetStrip(state: state, compact: true, onSelect: { grid in
                if state.settings.tileAllAppWindows { state.tileApplication(window, requestedGrid: grid) }
            })
            if let feedback = state.appTileFeedback,
               feedback.request.target.app.pid == window.app.pid {
                VStack(alignment: .leading, spacing: 7) {
                    Label(Localization.tf("%@ was not applied", feedback.request.grid.label), systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(feedback.message).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true).help(feedback.message)
                    if let grid = feedback.suggestedGrid {
                        Button(Localization.tf("Try %@ instead", grid.label)) { state.useSuggestedGrid(for: feedback.request.target) }
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
                Text(state.settings.tileAllAppWindows ? Localization.t("Preset: tile all · Drag: same size for all") : Localization.t("Drag to span · Release to resize"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(region.columnSpan) × \(region.rowSpan)").font(.caption.monospacedDigit()).foregroundStyle(PaneStyle.accent)
            }
            HStack {
                if state.settings.tileAllAppWindows {
                    Button(Localization.t("Tile app windows")) { state.tileApplication(window) }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("picker.tile-app-now")
                } else {
                    Button(Localization.t("Fill")) { state.snap(window, to: .init(column: 0, row: 0, columnSpan: state.settings.grid.columns, rowSpan: state.settings.grid.rows)) }
                    Button(Localization.t("Center")) { state.center(window) }
                }
                Button(Localization.t("Undo")) { state.undo() }.disabled(state.undoDepth == 0)
                Spacer()
                Button(Localization.t("Workspace…")) { close(); state.onShowWorkspace?() }
            }.controlSize(.small)
            Divider()
            if state.settings.tileAllAppWindows {
                Toggle(Localization.t("Suggest a fitting grid if needed"), isOn: $state.settings.autoFitAppWindows)
                    .font(.caption).toggleStyle(.checkbox).accessibilityIdentifier("picker.auto-fit-app")
                Text(Localization.tf("%@ only. Presets never change automatically.", window.app.name))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Toggle(Localization.tf("Reflow my selected group (%ld)", state.selectedIDs.count), isOn: $state.settings.reflowSelection)
                    .font(.caption).toggleStyle(.checkbox)
            }
            Text(Localization.t("Blank cells stay empty. Esc closes. Shift + arrows changes the span."))
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.primary.opacity(0.1), lineWidth: 1))
        .tint(PaneStyle.accent).preferredColorScheme(state.colorScheme)
        .disabled(state.isBusy || state.isPaused)
    }
}
