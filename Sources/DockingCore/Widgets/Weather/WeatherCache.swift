import Foundation

final class WeatherCache {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let directory = (try? AppSupportDirectory.url()) ?? FileManager.default.temporaryDirectory
            self.fileURL = directory.appendingPathComponent("WeatherSnapshot.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> WeatherSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(WeatherSnapshot.self, from: data)
    }

    func save(_ snapshot: WeatherSnapshot) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            DockingLog.weather.error("Failed to save weather cache: \(error.localizedDescription)")
        }
    }

    static func isFresh(_ snapshot: WeatherSnapshot, intervalMinutes: Int, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.fetchedAt) < Double(max(15, intervalMinutes)) * 60
    }
}
