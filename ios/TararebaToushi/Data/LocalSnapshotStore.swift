import CryptoKit
import Foundation

nonisolated enum SnapshotOrigin: String, Codable, Sendable {
    // `bundled` is retained only to identify and ignore caches made by the old development build.
    case bundled, remote
}

nonisolated struct StoredSnapshot: Codable, Sendable {
    let identity: String
    var snapshot: DatasetSnapshot
    var origin: SnapshotOrigin
    var fetchedAt: Date?
    var checkedAt: Date?
}

nonisolated protocol SnapshotStore: Sendable {
    func load() async throws -> StoredSnapshot?
    func save(_ value: StoredSnapshot) async throws
}

actor LocalSnapshotStore: SnapshotStore {
    private let directory: URL
    private let identity: String
    private let mode: DatasetMode

    init(directory: URL, configuration: AppConfiguration) {
        self.directory = directory
        self.identity = configuration.cacheIdentity
        self.mode = configuration.mode
    }

    private var file: URL {
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("snapshot-\(digest).json")
    }

    func load() throws -> StoredSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 6 * 1024 * 1024 else { throw DataIssue("保存データが大きすぎます。") }
        let stored = try JSONDecoder().decode(StoredSnapshot.self, from: Data(contentsOf: file))
        guard stored.identity == identity else { throw DataIssue("保存データの配信元が一致しません。") }
        guard stored.origin == .remote, stored.fetchedAt != nil else { return nil }
        _ = try DatasetValidator.validate(stored.snapshot, mode: mode)
        return stored
    }

    func save(_ value: StoredSnapshot) throws {
        guard value.identity == identity else { throw DataIssue("保存先の識別情報が一致しません。") }
        guard value.origin == .remote, value.fetchedAt != nil else { throw DataIssue("未取得のデータは保存できません。") }
        _ = try DatasetValidator.validate(value.snapshot, mode: mode)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var flags = URLResourceValues()
        flags.isExcludedFromBackup = true
        try folder.setResourceValues(flags)
        let bytes = try JSONEncoder().encode(value)
        // One validated envelope; atomic replacement keeps both funds on the same version.
        try bytes.write(to: file, options: .atomic)
    }
}
