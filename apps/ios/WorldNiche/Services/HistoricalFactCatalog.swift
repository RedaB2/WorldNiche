import Combine
import Foundation

/// Shares one accepted publication across all readers, independent of private journal workspaces.
@MainActor
final class HistoricalFactCatalog: ObservableObject {
    typealias Fetch = @Sendable (URL) async throws -> Data
    static let shared: HistoricalFactCatalog = {
        var endpoint: URL? = URL(string: "https://worldniche.app/content/v1/historical-facts.json")!
        var cacheName = "historical-facts-v1.json"
        #if DEBUG && targetEnvironment(simulator)
        let process = ProcessInfo.processInfo
        if let value = process.environment["WORLDNICHE_FACT_CATALOG_URL"], let url = URL(string: value),
           url.scheme == "http", url.host == "127.0.0.1", url.port != nil, url.user == nil, url.password == nil {
            endpoint = url
            cacheName = "historical-facts-loopback-v1.json"
        } else if process.arguments.contains(where: { $0.hasPrefix("-worldniche-") && $0.hasSuffix("-fixture") }) {
            endpoint = nil
        }
        #endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let file = endpoint == nil ? nil : directory?.appendingPathComponent(cacheName)
        return HistoricalFactCatalog(bundled: CountryRepository.bundledFacts,
                                     countryIDs: Set(CountryRepository.countries.map(\.id)),
                                     file: file, endpoint: endpoint)
    }()

    @Published private(set) var countries: [String: [HistoricalFact]]
    private(set) var revision: Int
    private let countryIDs: Set<String>
    private let file: URL?
    private let endpoint: URL?
    private let fetch: Fetch
    private let now: () -> Date
    private var lastChecked: Date?
    private var request: Task<Void, Never>?

    init(bundled: FactCatalogSnapshot?, countryIDs: Set<String>, file: URL?, endpoint: URL?,
         now: @escaping () -> Date = Date.init, fetch: @escaping Fetch = download) {
        self.countryIDs = countryIDs
        self.file = file
        self.endpoint = endpoint
        self.now = now
        self.fetch = fetch
        var accepted = bundled
        if let file, let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
           let bytes = values.fileSize, bytes <= FactCatalogSnapshot.byteLimit,
           let data = try? Data(contentsOf: file),
           let cached = try? FactCatalogSnapshot.validated(data, countryIDs: countryIDs),
           cached.revision > (bundled?.revision ?? 0) || cached == bundled {
            accepted = cached
            lastChecked = values.contentModificationDate
        }
        countries = accepted?.countries ?? [:]
        revision = accepted?.revision ?? 0
    }

    subscript(_ iso: String) -> [HistoricalFact] { countries[iso] ?? [] }

    /// A pull-to-refresh bypasses the daily interval. Simultaneous readers share the request.
    func refresh(force: Bool = false) async {
        guard let endpoint, let file else { return }
        if let request {
            await request.value
            return
        }
        if !force, let lastChecked, (0..<86_400).contains(now().timeIntervalSince(lastChecked)) { return }
        let work = Task {
            defer { request = nil }
            do {
                let data = try await fetch(endpoint)
                let next = try FactCatalogSnapshot.validated(data, countryIDs: countryIDs)
                guard next.revision >= revision else { return }
                if next.revision == revision, next.countries != countries { return }

                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                let checked = now()
                try? FileManager.default.setAttributes([.modificationDate: checked], ofItemAtPath: file.path)
                lastChecked = checked
                if next.revision > revision {
                    revision = next.revision
                    countries = next.countries
                }
            } catch {
                // The currently accepted publication remains readable and a later refresh can retry.
            }
        }
        request = work
        await work.value
    }

    nonisolated static func download(_ endpoint: URL) async throws -> Data {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == endpoint, http.expectedContentLength <= Int64(FactCatalogSnapshot.byteLimit)
        else { bytes.task.cancel(); throw URLError(.badServerResponse) }
        var data = Data()
        if http.expectedContentLength > 0 { data.reserveCapacity(Int(http.expectedContentLength)) }
        for try await byte in bytes {
            guard data.count < FactCatalogSnapshot.byteLimit else {
                bytes.task.cancel()
                throw CocoaError(.fileReadTooLarge)
            }
            data.append(byte)
        }
        return data
    }
}
