import CryptoKit
import Foundation

/// Stale-while-revalidate memory + disk cache for SoundCloud API payloads.
/// Lets screens render cached data on frame 1 while refreshing silently in the background.
actor APICache {
    private final class Box: NSObject {
        let data: Data
        init(_ data: Data) { self.data = data }
    }

    private let memory = NSCache<NSString, Box>()
    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            self.directory = FileManager.default
                .urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("CloudPlayer/api", isDirectory: true)
        }
        memory.countLimit = 128
        memory.totalCostLimit = 24 * 1024 * 1024
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        let nsKey = key as NSString
        if let box = memory.object(forKey: nsKey),
           let decoded = try? JSONDecoder().decode(T.self, from: box.data) {
            return decoded
        }
        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        memory.setObject(Box(data), forKey: nsKey, cost: data.count)
        return decoded
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        memory.setObject(Box(data), forKey: key as NSString, cost: data.count)
        let url = fileURL(for: key)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func remove(key: String) {
        memory.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    func clearAll() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("\(hash).json")
    }
}

/// Decoded SoundCloud waveform JSON (`waveform_url` returns ~1800 amplitude bars).
struct SCWaveform: Codable, Sendable {
    let width: Int?
    let height: Int
    let samples: [Int]

    /// Normalized 0...1 samples downsampled to `targetBars` using peak-preserving bucketing.
    func normalizedBars(count targetBars: Int) -> [Double] {
        guard !samples.isEmpty, targetBars > 0 else { return [] }
        let maxVal = Double(max(height, samples.max() ?? 1, 1))
        if samples.count <= targetBars {
            return samples.map { min(max(Double($0) / maxVal, 0.06), 1.0) }
        }
        var out: [Double] = []
        out.reserveCapacity(targetBars)
        let stride = Double(samples.count) / Double(targetBars)
        for i in 0..<targetBars {
            let start = Int(Double(i) * stride)
            let end = min(Int(Double(i + 1) * stride), samples.count)
            guard start < end else { continue }
            var sum = 0.0
            for j in start..<end { sum += Double(samples[j]) }
            let avg = (sum / Double(end - start)) / maxVal
            out.append(min(max(avg, 0.06), 1.0))
        }
        return out
    }
}

/// Fetches and caches SoundCloud waveform JSON files in memory + disk.
actor WaveformCache {
    static let shared = WaveformCache()

    private let cache: APICache
    private let session: URLSession
    private var inFlight: [URL: Task<SCWaveform?, Never>] = [:]

    init(cache: APICache = APICache(directory: FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("CloudPlayer/waveforms", isDirectory: true))) {
        self.cache = cache
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func waveform(for url: URL) async -> SCWaveform? {
        let key = url.absoluteString
        if let cached = await cache.load(SCWaveform.self, key: key) {
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task<SCWaveform?, Never> {
            guard let (data, resp) = try? await session.data(from: url),
                  let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  let decoded = try? JSONDecoder().decode(SCWaveform.self, from: data) else {
                return nil
            }
            await cache.save(decoded, key: key)
            return decoded
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        return result
    }
}
