import SwiftUI
import PaneGridCore

struct PreferencesView: View {
    @ObservedObject var state: AppState
    @State private var excludedText = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("The green-button picker", systemImage: "cursorarrow.rays").font(.headline)
                        Toggle("Show the picker when hovering a window’s green button", isOn: $state.settings.hoverEnabled)
                        Toggle("Require the Option (⌥) key while hovering", isOn: $state.settings.requireOption)
                        Text("Hold a window’s green button for 0.45 seconds to open the picker, even with hover off; Option is not required. A short click keeps macOS’s normal fullscreen behavior. Press-and-hold needs a recently detected button and an available mouse event tap. Option-hover can help if the native tiling menu appears at the same time.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text("Hover delay").frame(width: 105, alignment: .leading)
                            Slider(value: $state.settings.hoverDelay, in: 0.15...1.5, step: 0.05)
                            Text(String(format: "%.2f s", state.settings.hoverDelay)).monospacedDigit().frame(width: 60)
                        }
                        Picker("Global shortcut", selection: $state.settings.shortcut) {
                            ForEach(PickerShortcut.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.frame(maxWidth: 360)
                        Toggle("Preview the destination before applying", isOn: $state.settings.showPreview)
                        Toggle("Tile all windows of the app whose picker I open", isOn: $state.settings.tileAllAppWindows)
                            .accessibilityIdentifier("settings.tile-all-app")
                        Toggle("Suggest alternate grids when an app needs larger tiles", isOn: $state.settings.autoFitAppWindows)
                        Text("Your chosen preset always stays selected. An alternative is applied only when you explicitly choose it; slow responses are not treated as minimum sizes.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("With app-wide tiling on, selecting a preset immediately fills equal-sized portions with that app’s windows. A drawn span sets the size for all of them. Other apps remain untouched; no checkboxes or one-by-one placement are needed.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Toggle("Reflow my selected group when I snap a window", isOn: $state.settings.reflowSelection)
                            .disabled(state.settings.tileAllAppWindows)
                        Text("Reflow packs only the windows checked in Workspace around your snapped tile. Unselected windows never join automatically.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Grid & spacing", systemImage: "square.grid.3x3").font(.headline)
                        GridDimensions(state: state)
                        spacingSlider("Between tiles", value: $state.settings.gap, range: 0...32)
                        spacingSlider("Display margin", value: $state.settings.margin, range: 0...64)
                        Text("Display edges follow the usable desktop, keeping the Dock and menu bar clear. Large grids work best with multi-cell spans when apps need more room.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("This Mac", systemImage: "desktopcomputer").font(.headline)
                        Picker("Appearance", selection: $state.settings.theme) {
                            ForEach(AppTheme.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                        }.pickerStyle(.segmented)
                        Toggle("Launch PaneGrid at login", isOn: Binding(get: { state.loginEnabled }, set: state.setLoginEnabled))
                        Toggle("Pause window management", isOn: $state.isPaused)
                        HStack {
                            Button("Accessibility settings") { WindowAccess.requestPermission() }
                            Button("Open practice windows") { state.openPracticeWindows() }
                        }
                        Text("Excluded apps (bundle identifiers, one per line)").font(.callout)
                        TextEditor(text: $excludedText).font(.system(.caption, design: .monospaced))
                            .frame(height: 70).padding(5).overlay(RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.12)))
                            .accessibilityLabel("Excluded application bundle identifiers")
                        HStack {
                            Text("Example: com.apple.finder").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Save exclusions") {
                                let ids = excludedText.split(whereSeparator: { $0.isNewline || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                                guard ids.count <= 100, ids.allSatisfy({ $0.count <= 255 }) else {
                                    state.notice = .init(text: "Use at most 100 bundle identifiers, each under 256 characters.", isError: true); return
                                }
                                state.settings.excludedBundleIDs = Array(Set(ids)).sorted()
                                state.notice = .init(text: "Excluded apps will not appear in the picker or workspace.")
                            }
                        }
                    }
                }
                Text("PaneGrid \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Built for your desktop, not a server. No accounts, telemetry, subscriptions, or screen recording.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.bottom, 8)
        }.onAppear { excludedText = state.settings.excludedBundleIDs.joined(separator: "\n") }
    }

    private func spacingSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: 1)
            Text("\(Int(value.wrappedValue)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}

struct SavedLayoutsView: View {
    @ObservedObject var state: AppState
    @State private var deleting: SavedLayout?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("\(state.layouts.count) layouts · empty slots are welcome").foregroundStyle(.secondary)
                Spacer()
                Button("Import…") { state.importConfiguration() }
                Button("Export…") { state.exportConfiguration() }
            }
            if state.layouts.isEmpty {
                Surface {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 42)).foregroundStyle(PaneStyle.violet)
                        Text("A place for every routine.").font(.title2.weight(.semibold))
                        Text("Make a layout in Workspace, give it a name, and save it here. Load it later without opening apps or guessing which document belongs where.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                        Button("Create a layout") { state.section = .workspace }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity).padding(.vertical, 45)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 16)], spacing: 16) {
                        ForEach(state.layouts) { layout in
                            Surface {
                                VStack(alignment: .leading, spacing: 14) {
                                    layoutThumbnail(layout).frame(height: 105)
                                    Text(layout.name).font(.headline)
                                    Text("\(layout.grid.label) · \(layout.slots.count) windows").font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        Button("Load into editor") { state.loadLayout(layout) }.disabled(state.isScanning || state.isBusy)
                                        Spacer()
                                        Button { deleting = layout } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                                            .accessibilityLabel("Delete \(layout.name)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text("Matching uses the app and exact window title. Missing or ambiguous matches remain empty. Imported layouts do not run code or launch apps.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .alert("Delete this layout?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let deleting { state.layouts.removeAll { $0.id == deleting.id } }
                deleting = nil
            }
        } message: { Text("Your windows will not be moved.") }
    }

    private func layoutThumbnail(_ layout: SavedLayout) -> some View {
        GridCanvas(grid: layout.grid, selection: .constant(.init(column: 0, row: 0, columnSpan: 0)),
                   labels: layout.slots.enumerated().map { index, slot in
            TileLabel(id: slot.id.uuidString, region: slot.region, text: "", color: PaneStyle.colors[index % PaneStyle.colors.count])
        }).allowsHitTesting(false).accessibilityHidden(true)
    }
}
