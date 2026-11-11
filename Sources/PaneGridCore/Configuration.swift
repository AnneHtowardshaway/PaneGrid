import Foundation

public enum AppTheme: String, CaseIterable, Codable, Sendable { case system, dark, light }
public enum PickerShortcut: String, CaseIterable, Codable, Sendable {
    case controlOptionSpace, controlShiftSpace, disabled
    public var label: String {
        switch self {
        case .controlOptionSpace: return "⌃⌥ Space"
        case .controlShiftSpace: return "⌃⇧ Space"
        case .disabled: return Localization.t("Disabled")
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var grid = GridSize(columns: 4, rows: 4)
    public var gap: Double = 8
    public var margin: Double = 8
    public var hoverEnabled = true
    public var requireOption = false
    public var hoverDelay: Double = 0.3
    public var showPreview = true
    public var reflowSelection = false
    public var tileAllAppWindows = false
    public var autoFitAppWindows = true
    public var theme: AppTheme = .system
    public var shortcut: PickerShortcut = .controlOptionSpace
    public var excludedBundleIDs: [String] = []
    public var language: AppLanguage = .system
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case grid, gap, margin, hoverEnabled, requireOption, hoverDelay, showPreview, reflowSelection
        case tileAllAppWindows, autoFitAppWindows, theme, shortcut, excludedBundleIDs, language
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        grid = try values.decode(GridSize.self, forKey: .grid)
        gap = try values.decode(Double.self, forKey: .gap)
        margin = try values.decode(Double.self, forKey: .margin)
        hoverEnabled = try values.decode(Bool.self, forKey: .hoverEnabled)
        requireOption = try values.decode(Bool.self, forKey: .requireOption)
        hoverDelay = try values.decode(Double.self, forKey: .hoverDelay)
        showPreview = try values.decode(Bool.self, forKey: .showPreview)
        reflowSelection = try values.decode(Bool.self, forKey: .reflowSelection)
        theme = try values.decode(AppTheme.self, forKey: .theme)
        shortcut = try values.decode(PickerShortcut.self, forKey: .shortcut)
        excludedBundleIDs = try values.decode([String].self, forKey: .excludedBundleIDs)
        // Version 1 files predate these controls. Preserve every old field without discarding user layouts.
        tileAllAppWindows = try values.decodeIfPresent(Bool.self, forKey: .tileAllAppWindows) ?? false
        autoFitAppWindows = try values.decodeIfPresent(Bool.self, forKey: .autoFitAppWindows) ?? true
        language = try values.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
    }

    public func validate() throws {
        guard gap.isFinite, margin.isFinite, hoverDelay.isFinite,
              (0...32).contains(gap), (0...64).contains(margin),
              (0.15...1.5).contains(hoverDelay), excludedBundleIDs.count <= 100,
              excludedBundleIDs.allSatisfy({ !$0.isEmpty && $0.count <= 255 }) else { throw GridError.invalidConfiguration }
    }
}

public struct WindowIdentity: Codable, Hashable, Sendable {
    public var bundleID: String
    public var title: String
    public var ordinal: Int
    public init(bundleID: String, title: String, ordinal: Int = 0) {
        self.bundleID = bundleID; self.title = title; self.ordinal = ordinal
    }
}

public struct SavedSlot: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var region: GridRegion
    public var window: WindowIdentity
    public init(region: GridRegion, window: WindowIdentity) {
        id = UUID(); self.region = region; self.window = window
    }
}

public struct SavedLayout: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var grid: GridSize
    public var slots: [SavedSlot]
    public init(name: String, grid: GridSize, slots: [SavedSlot]) {
        id = UUID(); self.name = name; self.grid = grid; self.slots = slots
    }

    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              slots.count <= grid.count, Set(slots.map(\.id)).count == slots.count,
              Set(slots.map { [$0.window.bundleID, $0.window.title] }).count == slots.count else { throw GridError.invalidConfiguration }
        for (index, slot) in slots.enumerated() {
            guard slot.region.isValid(in: grid), !slot.window.bundleID.isEmpty,
                  slot.window.bundleID.count <= 255, slot.window.title.count <= 4096,
                  slot.window.ordinal == 0,
                  !slots.prefix(index).contains(where: { $0.region.intersects(slot.region) }) else {
                throw GridError.invalidConfiguration
            }
        }
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var settings = AppSettings()
    public var layouts: [SavedLayout] = []
    public init() {}
    public func validate() throws {
        guard schemaVersion == 1, layouts.count <= 100,
              Set(layouts.map(\.id)).count == layouts.count else { throw GridError.invalidConfiguration }
        try settings.validate()
        try layouts.forEach { try $0.validate() }
    }

    public static func decode(_ data: Data) throws -> Configuration {
        guard data.count <= 2_000_000 else { throw GridError.invalidConfiguration }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public enum SavedWindowMatcher {
    /// A window's z-order/ordinal is not a persistent identity. Refuse duplicate titles even if ordinals differ.
    public static func match(_ saved: WindowIdentity, candidates: [(id: String, identity: WindowIdentity)],
                             excluding used: Set<String> = []) -> String? {
        let matches = candidates.filter { $0.identity.bundleID == saved.bundleID && $0.identity.title == saved.title }
        guard saved.ordinal == 0, matches.count == 1, matches[0].identity == saved,
              !used.contains(matches[0].id) else { return nil }
        return matches[0].id
    }
}
