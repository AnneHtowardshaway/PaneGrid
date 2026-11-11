import Foundation
import PaneGridCore

final class LocalStore {
    let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PaneGrid", isDirectory: true)
    var fileURL: URL { directory.appendingPathComponent("configuration.json") }
    private var protectsUnreadableOriginal = false

    /// 读盘告警以文案键返回，避免在 `AppState` 设定语言之前就把文本定死。
    func load() -> (Configuration, AppNotice?) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (Configuration(), nil) }
        do { return (try Configuration.decode(readBounded(fileURL)), nil) }
        catch {
            // Preserve the original, including newer schema versions, before accepting any edits.
            let backup = directory.appendingPathComponent("configuration-preserved-\(UUID().uuidString).json")
            do { try FileManager.default.copyItem(at: fileURL, to: backup) }
            catch { protectsUnreadableOriginal = true }
            return (Configuration(), protectsUnreadableOriginal
                    ? .init(key: "Settings could not be read or backed up. Saving is disabled to protect the original file.", isError: true)
                    : .init(key: "Settings could not be read. The original was preserved in Application Support; defaults are in use.", isError: true))
        }
    }

    func save(_ configuration: Configuration) throws {
        guard !protectsUnreadableOriginal else { throw GridError.invalidConfiguration }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try configuration.encoded().write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 2_000_000 else { throw GridError.invalidConfiguration }
        return try Data(contentsOf: url)
    }
}
