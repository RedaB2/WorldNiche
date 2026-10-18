import Foundation

/// Only guest photos are persisted locally. Remote friend photos are never written here.
enum AvatarPhotoFiles {
    private static func directory(_ override: URL?) -> URL {
        if let override { return override }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorldNiche-ProfilePhotos", isDirectory: true)
    }

    static func save(_ data: Data, directory override: URL? = nil) throws -> String {
        let directory = directory(override)
        guard AvatarPhotoReference.isValidJPEG(data) else { throw SocialError.invalidPhoto }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID().uuidString.lowercased()
        try data.write(to: directory.appendingPathComponent("\(id).jpg"), options: [.atomic, .completeFileProtectionUnlessOpen])
        return id
    }

    static func load(_ id: String, directory override: URL? = nil) -> Data? {
        let directory = directory(override)
        guard UUID(uuidString: id)?.uuidString.lowercased() == id else { return nil }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(id).jpg")),
              AvatarPhotoReference.isValidJPEG(data) else { return nil }
        return data
    }

    static func remove(_ id: String, directory override: URL? = nil) {
        let directory = directory(override)
        guard UUID(uuidString: id)?.uuidString.lowercased() == id else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).jpg"))
    }

    static func removeAll(directory override: URL? = nil) { try? FileManager.default.removeItem(at: directory(override)) }
}
