import Foundation

/// Meal history kept in a directory on the device: one JSON file per meal entry and one file per
/// meal photo. A new instance over the same directory sees everything saved before (survives relaunch).
public final class FileMealHistoryStore: MealHistoryStore {
    private let entriesDirectory: URL
    private let photosDirectory: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    public init(directory: URL) throws {
        entriesDirectory = directory.appendingPathComponent("MealEntries", isDirectory: true)
        photosDirectory = directory.appendingPathComponent("MealPhotos", isDirectory: true)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
    }

    public func save(_ entry: MealEntry, photoData: [MealPhoto.ID: Data]) throws {
        for photo in entry.photos where photoData[photo.id] == nil {
            guard FileManager.default.fileExists(atPath: photoURL(for: photo).path) else {
                throw MealHistoryStoreError.missingPhotoData(photo.id)
            }
        }
        for photo in entry.photos {
            if let data = photoData[photo.id] {
                try data.write(to: photoURL(for: photo), options: .atomic)
            }
        }
        try encoder.encode(entry).write(to: entryURL(for: entry.id), options: .atomic)
    }

    public func mealEntries() throws -> [MealEntry] {
        try FileManager.default
            .contentsOfDirectory(at: entriesDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try decoder.decode(MealEntry.self, from: Data(contentsOf: $0)) }
    }

    public func mealEntry(id: MealEntry.ID) throws -> MealEntry? {
        let url = entryURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(MealEntry.self, from: Data(contentsOf: url))
    }

    public func photoData(for photo: MealPhoto) throws -> Data {
        let url = photoURL(for: photo)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MealHistoryStoreError.missingPhotoData(photo.id)
        }
        return try Data(contentsOf: url)
    }

    private func entryURL(for id: MealEntry.ID) -> URL {
        entriesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func photoURL(for photo: MealPhoto) -> URL {
        photosDirectory.appendingPathComponent(photo.fileName)
    }
}
