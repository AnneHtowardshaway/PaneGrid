import SwiftUI
import PaneGridCore

struct PaneGridRootView: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                header
                if !state.isTrusted { permissionBanner }
                Group {
                    switch state.section {
                    case .workspace: WorkspaceView(state: state)
                    case .layouts: SavedLayoutsView(state: state)
                    case .settings: PreferencesView(state: state)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                notice
            }.padding(26).padding(.top, 12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(PaneStyle.accent)
        .preferredColorScheme(state.colorScheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                PaneMark()
                Text("PaneGrid").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(Localization.t("A little more room.")).font(.callout).foregroundStyle(.secondary)
            }.padding(.horizontal, 10)
            VStack(spacing: 6) {
                ForEach(WorkspaceSection.allCases, id: \.self) { section in
                    Button { state.section = section } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol).frame(width: 20)
                            Text(section.title).fontWeight(state.section == section ? .semibold : .regular)
                            Spacer()
                        }.padding(12)
                            .foregroundStyle(state.section == section ? PaneStyle.accent : .primary)
                            .background(state.section == section ? PaneStyle.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text(Localization.t("QUICK PICKER")).font(.system(size: 10, weight: .semibold)).tracking(1.6).foregroundStyle(.tertiary)
                Text(state.settings.shortcut.label).font(.system(.callout, design: .monospaced))
                Text(Localization.t("Or hover / hold a window’s green button.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Label(state.isPaused ? Localization.t("Paused") : state.isTrusted ? Localization.t("Ready on this Mac") : Localization.t("Permission needed"),
                      systemImage: state.isTrusted && !state.isPaused ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(state.isTrusted && !state.isPaused ? PaneStyle.accent : .orange)
                Text(Localization.t("LOCAL · FREE · OPEN SOURCE")).font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.tertiary)
            }.padding(10)
        }.padding(18).padding(.top, 34)
            .background(LinearGradient(colors: [PaneStyle.accent.opacity(0.035), PaneStyle.violet.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(state.section == .workspace ? Localization.t("YOUR WINDOW WORKSPACE") : state.section == .layouts ? Localization.t("ROOM FOR YOUR ROUTINES") : Localization.t("MAKE IT YOURS"))
                    .font(.system(size: 10, weight: .semibold)).tracking(1.7).foregroundStyle(PaneStyle.accent)
                Text(state.section == .workspace ? Localization.t("Everything in its place.") : state.section == .layouts ? Localization.t("Keep a good arrangement.") : Localization.t("Small details. Your way."))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 12)
            Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .help(Localization.t("Undo last arrangement")).disabled(state.undoDepth == 0 || state.isBusy)
                .accessibilityLabel(Localization.t("Undo last arrangement"))
            Button(Localization.t("Open picker")) { state.onShowPicker?() }.disabled(!state.isTrusted || state.isBusy || state.isPaused)
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(Localization.t("One permission, then you’re ready.")).fontWeight(.semibold)
                Text(Localization.t("Allow Accessibility access so PaneGrid can move and resize your windows. No screen recording is needed."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(Localization.t("Enable window control")) { WindowAccess.requestPermission() }.buttonStyle(.borderedProminent)
        }.padding(16).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: 9) {
            if state.isBusy { ProgressView().controlSize(.small) }
            else { Image(systemName: state.notice.isError ? "exclamationmark.triangle" : "info.circle").foregroundStyle(state.notice.isError ? .orange : PaneStyle.accent) }
            Text(state.notice.text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if state.isBusy {
                Button(state.cancelRequested ? Localization.t("Restoring…") : Localization.t("Cancel")) { state.cancelArrangement() }
                    .disabled(state.cancelRequested).controlSize(.small).accessibilityIdentifier("workspace.cancel-arrangement")
            }
        }.frame(minHeight: 28, alignment: .top)
    }
}

struct WorkspaceView: View {
    @ObservedObject var state: AppState
    @State private var layoutName = ""
    private var listedWindows: [LiveWindow] {
        state.windows.filter { state.windowSearch.isEmpty || "\($0.app.name) \($0.title)".localizedCaseInsensitiveContains(state.windowSearch) }
    }
    private var labels: [TileLabel] {
        state.windows.enumerated().compactMap { index, window in
            guard let region = state.assignments[window.id] else { return nil }
            return TileLabel(id: window.id, region: region, text: window.app.name, color: PaneStyle.colors[index % PaneStyle.colors.count])
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Label(Localization.t("Display"), systemImage: "display").foregroundStyle(.secondary)
                Picker(Localization.t("Display"), selection: $state.displayID) {
                    ForEach(state.displays) { display in Text(display.name).tag(display.id) }
                }.labelsHidden().frame(maxWidth: 230)
                Spacer()
                Text(Localization.t("Draw first. Arrange when ready.")).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(Localization.t("Your grid")).font(.headline)
                            Spacer()
                            Text(Localization.t("COLUMNS × ROWS")).font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.tertiary)
                        }
                        PresetStrip(state: state)
                        GridDimensions(state: state)
                        GridCanvas(grid: state.settings.grid, selection: $state.region, labels: labels,
                                   onCommit: { state.assignSelectedRegion($0) })
                            .frame(minHeight: 180, maxHeight: .infinity)
                            .accessibilityIdentifier("workspace.grid")
                        HStack {
                            Label(Localization.tf("%ld × %ld selected", state.region.columnSpan, state.region.rowSpan), systemImage: "selection.pin.in.out")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(Localization.t("Clear region")) { state.clearRegion() }.controlSize(.small)
                            Button(Localization.t("Reset")) { state.assignments = [:] }.controlSize(.small)
                        }
                        Text(Localization.t("Click window cards to select them, then Apply to tile them together. With one window selected, drag on the grid to set its exact region."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                windowList.frame(width: 260)
            }.frame(maxHeight: .infinity)
            HStack(spacing: 10) {
                TextField(Localization.t("Name this layout…"), text: $layoutName).textFieldStyle(.roundedBorder).frame(maxWidth: 210)
                Button(Localization.t("Save layout")) { state.saveLayout(named: layoutName); layoutName = "" }
                    .disabled(layoutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Text(Localization.tf("%ld assigned", state.assignments.count)).font(.caption).foregroundStyle(.secondary)
                Button { state.applyDraft() } label: { Label(Localization.t("Apply arrangement"), systemImage: "arrow.up.right.and.arrow.down.left.rectangle") }
                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(!state.canArrange)
                    .accessibilityIdentifier("workspace.apply")
            }
        }.disabled(state.isBusy)
    }

    private var windowList: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Localization.t("Windows")).font(.headline)
                    Spacer()
                    if state.isScanning { ProgressView().controlSize(.small) }
                    Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help(Localization.t("Refresh open windows")).disabled(state.isScanning || !state.isTrusted)
                        .accessibilityLabel(Localization.t("Refresh windows"))
                }
                TextField(Localization.t("Filter apps or titles…"), text: $state.windowSearch).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Localization.t("Filter windows"))
                HStack {
                    Button(Localization.t("Select listed")) { state.selectedIDs.formUnion(listedWindows.map(\.id)) }
                    Spacer()
                    Button(Localization.t("None")) { state.selectedIDs = []; state.assignments = [:] }
                }.font(.caption).buttonStyle(.plain).foregroundStyle(PaneStyle.accent)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(listedWindows) { window in windowRow(window) }
                        if listedWindows.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "macwindow.badge.plus").font(.largeTitle).foregroundStyle(.tertiary)
                                Text(state.isTrusted ? Localization.t("No matching windows") : Localization.t("Windows appear after you enable access."))
                                    .font(.callout).multilineTextAlignment(.center).foregroundStyle(.secondary)
                                Button(Localization.t("Open practice windows")) { state.openPracticeWindows() }.controlSize(.small)
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                    }
                }.frame(maxHeight: .infinity)
                Divider()
                Button { state.autoPlace() } label: { Label(Localization.t("Auto-place selected"), systemImage: "square.grid.3x3.fill").frame(maxWidth: .infinity) }
                    .disabled(state.selectedIDs.isEmpty)
                Text(Localization.t("Click anywhere on a card to select or deselect it. Only selected windows are arranged."))
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxHeight: .infinity)
    }

    private func windowRow(_ window: LiveWindow) -> some View {
        Button { state.toggleSelection(window) } label: {
            HStack(spacing: 10) {
                Image(systemName: state.selectedIDs.contains(window.id) ? "checkmark.square.fill" : "square")
                    .font(.title3).foregroundStyle(state.selectedIDs.contains(window.id) ? PaneStyle.accent : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(window.app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(window.displayTitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    if let placement = state.assignments[window.id] {
                        Text(Localization.tf("%ld × %ld · C%ld R%ld", placement.columnSpan, placement.rowSpan, placement.column + 1, placement.row + 1))
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(PaneStyle.accent)
                    }
                }
                Spacer(minLength: 0)
            }.padding(10).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(state.selectedIDs.contains(window.id) ? PaneStyle.accent.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(state.selectedIDs.contains(window.id) ? PaneStyle.accent.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(Localization.tf("Select %@, %@", window.app.name, window.displayTitle))
            .accessibilityValue(state.selectedIDs.contains(window.id) ? Localization.t("Selected") : Localization.t("Not selected"))
            .accessibilityIdentifier("workspace.window.\(window.id)")
    }
}
