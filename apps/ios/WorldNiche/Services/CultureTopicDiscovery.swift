import Foundation

/// Searches several facets of everyday culture and follows MediaWiki continuation
/// cursors. A consumed pool is replenished, never treated as a fixed daily deck.
actor CultureTopicDiscovery {
    private struct Pool {
        var titles: [String] = []
        var countryLinkedTitles: Set<String> = []
        var offsets: [Int: Int] = [:]
        var exhausted: Set<Int> = []
        var nextFacet = 0
        var fetchedAt: Date
        var retryAfter: Date?
    }
    private struct Page { let titles: [String]; let countryLinkedTitles: Set<String>; let nextOffset: Int? }
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var cache: [String: Pool] = [:]
    private var backoffUntil: Date?
    private struct Flight {
        let id: UUID
        let task: Task<[String], Never>
        var waiters: Set<UUID>
    }
    private var inFlight: [String: Flight] = [:]

    #if WORLDNICHE_TESTING
    func pendingSubscriberCount(for countryID: String) -> Int {
        inFlight[countryID]?.waiters.count ?? 0
    }
    #endif

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    func topics(for country: Country, excluding: Set<String> = [], minimumCount: Int = 6, preferCountryLinked: Bool = false) async -> [String] {
        guard !Task.isCancelled else { return [] }
        let excluded = Set(excluding.map(Self.normalized))
        let waiterID = UUID()
        let flight: Flight
        if var pending = inFlight[country.id] {
            pending.waiters.insert(waiterID)
            inFlight[country.id] = pending
            flight = pending
        } else {
            let task = Task { await discover(for: country, excluding: excluded, minimumCount: max(1, min(12, minimumCount)), preferCountryLinked: preferCountryLinked) }
            flight = Flight(id: UUID(), task: task, waiters: [waiterID])
            inFlight[country.id] = flight
        }
        let result = await withTaskCancellationHandler {
            await flight.task.value
        } onCancel: {
            Task { await self.releaseWaiter(waiterID, flightID: flight.id, countryID: country.id, cancelled: true) }
        }
        releaseWaiter(waiterID, flightID: flight.id, countryID: country.id, cancelled: false)
        guard !Task.isCancelled else { return [] }
        // All callers get their own history filter, including coalesced waiters.
        return (cache[country.id]?.titles ?? result).filter { !excluded.contains(Self.normalized($0)) }
    }

    func hasCountryContext(title: String, country: Country) -> Bool {
        cache[country.id]?.countryLinkedTitles.contains(Self.normalized(title)) == true
    }

    private func releaseWaiter(_ waiterID: UUID, flightID: UUID, countryID: String, cancelled: Bool) {
        guard var flight = inFlight[countryID], flight.id == flightID else { return }
        flight.waiters.remove(waiterID)
        if flight.waiters.isEmpty {
            if cancelled { flight.task.cancel() }
            inFlight.removeValue(forKey: countryID)
        } else { inFlight[countryID] = flight }
    }

    private func discover(for country: Country, excluding: Set<String>, minimumCount: Int, preferCountryLinked: Bool) async -> [String] {
        let date = now()
        var pool = cache[country.id] ?? Pool(fetchedAt: date)
        if date.timeIntervalSince(pool.fetchedAt) >= 86_400 { pool = Pool(fetchedAt: date) }
        func available() -> [String] { pool.titles.filter { !excluding.contains(Self.normalized($0)) } }
        func hasEnough() -> Bool {
            let titles = available()
            return titles.count >= minimumCount && (!preferCountryLinked || titles.contains { pool.countryLinkedTitles.contains(Self.normalized($0)) })
        }
        if hasEnough() { return available() }
        if let until = backoffUntil, until > date { return available() }
        if let until = pool.retryAfter, until > date { return available() }
        guard let identity = Self.identities[country.id] else { return available() }
        // Bound work per tap. Subsequent taps continue at saved cursors/facets.
        for _ in 0..<3 {
            guard pool.exhausted.count < Self.facets.count else { break }
            while pool.exhausted.contains(pool.nextFacet) { pool.nextFacet = (pool.nextFacet + 1) % Self.facets.count }
            let facet = pool.nextFacet
            do {
                try Task.checkCancellation()
                let page = try await search(identity: identity, country: country, facet: facet,
                                            offset: pool.offsets[facet, default: 0])
                if let next = page.nextOffset, next > pool.offsets[facet, default: 0] { pool.offsets[facet] = next }
                else { pool.exhausted.insert(facet) }
                pool.nextFacet = (facet + 1) % Self.facets.count
                var seen = Set(pool.titles.map(Self.normalized))
                pool.titles += page.titles.filter { seen.insert(Self.normalized($0)).inserted }
                pool.countryLinkedTitles.formUnion(page.countryLinkedTitles)
                // Prefer explicit country evidence across the whole pool, so broad
                // regional hits cannot spend every summary attempt before a local practice.
                pool.titles = pool.titles.enumerated().sorted {
                    let left = pool.countryLinkedTitles.contains(Self.normalized($0.element))
                    let right = pool.countryLinkedTitles.contains(Self.normalized($1.element))
                    return left == right ? $0.offset < $1.offset : left
                }.map(\.element)
                pool.retryAfter = nil
                cache[country.id] = pool
                if hasEnough() { break }
            } catch {
                if Task.isCancelled { return [] }
                pool.retryAfter = now().addingTimeInterval(60)
                cache[country.id] = pool
                break // Preserve any successful page before a failed top-up.
            }
        }
        cache[country.id] = pool
        return available()
    }

    // Specific social practices come first; food/music is a later discovery facet.
    // These are query themes, not a hardcoded bank of country facts.
    private static let facets = [
        "\"custom\"", "\"ritual\"", "\"festival\"", "\"subculture\"",
        "\"etiquette\"", "\"craft\"", "\"tradition\" articletopic:food-and-drink|music|performing-arts|fashion",
        "\"traditional\" articletopic:food-and-drink|music|performing-arts|fashion"
    ]

    private func search(identity: Identity, country: Country, facet: Int, offset: Int) async throws -> Page {
        try Task.checkCancellation()
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        let query = "articlecountry:\(identity.iso3) \(Self.facets[facet]) -articletopic:biography -hastemplate:\"Infobox album\" -hastemplate:\"Infobox single\" -intitle:\"List of\" -intitle:\"History of\" -intitle:\"Timeline of\""
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"), URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: query), URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "gsrlimit", value: "20"), URLQueryItem(name: "gsroffset", value: String(offset)),
            URLQueryItem(name: "prop", value: "description"), URLQueryItem(name: "gsrsort", value: "relevance")
        ]
        guard let url = components.url else { throw DiscoveryError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("WorldNiche/1.0 (native cultural discovery; public Wikimedia search)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw DiscoveryError.invalidResponse }
        if http.statusCode == 429 {
            let seconds = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            backoffUntil = now().addingTimeInterval(max(60, min(seconds, 3600)))
            throw DiscoveryError.rateLimited
        }
        guard (200..<300).contains(http.statusCode), data.count < 1_000_000 else { throw DiscoveryError.invalidResponse }
        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        if payload.error?.code == "ratelimited" {
            backoffUntil = now().addingTimeInterval(60)
            throw DiscoveryError.rateLimited
        }
        guard payload.error == nil, payload.warnings?.isEmpty != false,
              let results = payload.query?.pages else { throw DiscoveryError.invalidResponse }
        let titles = results.filter { $0.ns == 0 && Self.isRelevant($0, country: country, identity: identity) }
            .sorted {
                let left = Self.specificity($0), right = Self.specificity($1)
                return left == right ? ($0.index ?? Int.max) < ($1.index ?? Int.max) : left > right
            }.map(\.title)
        let linked = results.filter { result in
            let text = Self.normalized(result.description ?? "")
            return identity.aliases.contains { Self.containsWord(Self.normalized($0), in: text) }
        }.map { Self.normalized($0.title) }
        return Page(titles: titles, countryLinkedTitles: Set(linked), nextOffset: payload.continuation?.gsroffset)
    }

    private static func isRelevant(_ result: SearchResult, country: Country, identity: Identity) -> Bool {
        let title = normalized(result.title)
        let snippet = normalized(plainText(result.description ?? ""))
        guard !snippet.isEmpty, !isGeographicSubject(snippet) else { return false }
        let text = title + " " + snippet
        guard !title.isEmpty, title.count <= 200, !title.contains(":"), title != normalized(country.name),
              !["culture of ", "list of ", "history of ", "timeline of ", "geography of ", "politics of ", "music of ", "religion in ", "death of "] .contains(where: title.hasPrefix),
              !title.contains("(disambiguation)"), !title.hasSuffix(" cuisine"), !title.hasSuffix(" folklore"),
              !title.hasSuffix(" mythology"), !title.hasSuffix(" literature") else { return false }
        let excluded = ["composer", "singer", "rapper", "ensemble", "music group", "musical group", "band", "songwriter", "actress", "actor", "politician", "symphony", "sonata", "concerto", "album", "discography", "film", "anime", "video game", "television series", "company", "manufacturer", "military", "regiment", "election", "massacre", "genocide", "civil war", "archaeological site", "ancient city", "olympics", "civil law", "customary law", "legislation", "legal system", "treaty", "constitution", "roller coaster", "motor vehicle", "automobile", "architect", "sect", "cult", "terrorism", "murder", "suicide"]
        guard !excluded.contains(where: { containsWord($0, in: text) }),
              snippet.range(of: #"\bborn\s+(?:on\s+)?(?:\d|[a-z]+\s+\d)"#, options: .regularExpression) == nil,
              culturalTerms.contains(where: { containsWord($0, in: text) }) else { return false }
        // Country classifiers handle named regional practices whose snippet may
        // mention a village/community instead of repeating the country name.
        // Retain explicit disambiguation guards for common geographic collisions.
        if country.id == "GE", text.contains("atlanta") || text.contains("u.s. state") { return false }
        if country.id == "DM", text.contains("dominican republic") { return false }
        if country.id == "GN", ["papua new guinea", "equatorial guinea", "guinea-bissau"].contains(where: text.contains) { return false }
        let otherExplicitCountry = identities.values.contains { other in
            other.iso3 != identity.iso3 && other.aliases.contains { $0.count > 3 && containsWord(normalized($0), in: text) }
        }
        if otherExplicitCountry && !identity.aliases.contains(where: { containsWord(normalized($0), in: text) }) { return false }
        return true
    }

    private static func specificity(_ result: SearchResult) -> Int {
        let text = normalized(plainText(result.description ?? ""))
        return ["custom", "ritual", "etiquette", "greeting", "community", "village", "regional", "local", "seasonal", "ceremony", "subculture", "practice"].reduce(0) { $0 + (containsWord($1, in: text) ? 2 : 0) }
    }

    static func isCulturalSummary(_ text: String, country: Country? = nil, hasCountryContext: Bool = false) -> Bool {
        let lead = normalized(String(text.prefix(900)))
        let unrelated = ["is a village", "is a town", "is a city", "is a municipality", "is a commune", "is a political", "is a company", "is an archaeological", "is a temple", "is a church", "is a mountain", "is a railway", "roller coaster", "motor vehicle", "automobile", "civil law", "customary law", "law of the land", "was a traditional", "was an ancient"]
        guard text.count >= 140, !isGeographicSubject(lead), !unrelated.contains(where: lead.contains) else { return false }
        if let country, let identity = identities[country.id] {
            let namesPlace = identity.aliases.contains { containsWord(normalized($0), in: lead) }
            let namesAnotherPlace = identities.values.contains { other in
                other.iso3 != identity.iso3 && other.aliases.contains { $0.count > 3 && containsWord(normalized($0), in: lead) }
            }
            guard namesPlace || (hasCountryContext && !namesAnotherPlace) else { return false }
        }
        return culturalTerms.contains(where: { containsWord($0, in: lead) })
    }

    private static func isGeographicSubject(_ text: String) -> Bool {
        let pattern = #"(?:^|\bis\s+(?:a|an)\s+)(?:(?:traditional|historical|historic|geographical|geographic|administrative|cultural|disputed)\s+)?(?:region|oasis|city|town|village|municipality|commune|province|district|territory|mountain|island|archipelago|valley|river|lake|settlement)\b(?:\s+(?:in|of|on|within)\b|,|\.|$)"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func normalized(_ value: String) -> String {
        plainText(value).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "_", with: " ").lowercased()
    }
    private static func containsWord(_ word: String, in text: String) -> Bool {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }
    private static let culturalTerms = [
        "custom", "customs", "ritual", "rituals", "etiquette", "greeting", "subculture", "practice", "ceremony", "ceremonial", "celebration", "celebrate", "festival", "festivals", "tradition", "traditional", "dance", "dances", "dancing", "folk music", "music genre", "genre", "musical instrument", "game", "craft", "weaving", "textile", "clothing", "garment", "headdress", "bathing", "bath", "communal", "festive", "seasonal", "gifting", "market", "costume", "mask", "folklore", "cuisine", "culinary", "food", "dish", "bread", "soup", "cake", "noodles", "tea", "coffee", "rice", "cheese", "stew", "dessert", "meal", "snack", "pastry", "dumpling", "drink", "beverage", "beer", "wine"
    ]
    private enum DiscoveryError: Error { case invalidResponse, rateLimited }
    private struct SearchResponse: Decodable {
        let query: Query?
        let error: APIError?
        let warnings: [String: Warning]?
        let continuation: Continuation?
        enum CodingKeys: String, CodingKey { case query, error, warnings; case continuation = "continue" }
        struct Continuation: Decodable { let gsroffset: Int? }
        struct Query: Decodable { let pages: [SearchResult] }
        struct APIError: Decodable { let code: String }
        struct Warning: Decodable { }
    }
    private struct SearchResult: Decodable { let ns: Int; let title: String; let description: String?; let index: Int? }
    private struct Identity: Sendable { let iso3: String; let aliases: [String] }
    // Geographic identity data only; this is not a collection of cultural facts.
    // ISO codes and English demonyms adapted from the app's mledoze/countries source.
    private static let identities: [String: Identity] = [
        "AF": Identity(iso3: "afg", aliases: ["Afghanistan", "Afghan"]),
        "AL": Identity(iso3: "alb", aliases: ["Albania", "Albanian"]),
        "DZ": Identity(iso3: "dza", aliases: ["Algeria", "Algerian"]),
        "AD": Identity(iso3: "and", aliases: ["Andorra", "Andorran"]),
        "AO": Identity(iso3: "ago", aliases: ["Angola", "Angolan"]),
        "AG": Identity(iso3: "atg", aliases: ["Antigua and Barbuda", "Antiguan", "Barbudan"]),
        "AR": Identity(iso3: "arg", aliases: ["Argentina", "Argentine"]),
        "AM": Identity(iso3: "arm", aliases: ["Armenia", "Armenian"]),
        "AU": Identity(iso3: "aus", aliases: ["Australia", "Australian"]),
        "AT": Identity(iso3: "aut", aliases: ["Austria", "Austrian"]),
        "AZ": Identity(iso3: "aze", aliases: ["Azerbaijan", "Azerbaijani"]),
        "BS": Identity(iso3: "bhs", aliases: ["Bahamas", "Bahamian"]),
        "BH": Identity(iso3: "bhr", aliases: ["Bahrain", "Bahraini"]),
        "BD": Identity(iso3: "bgd", aliases: ["Bangladesh", "Bangladeshi"]),
        "BB": Identity(iso3: "brb", aliases: ["Barbados", "Barbadian"]),
        "BY": Identity(iso3: "blr", aliases: ["Belarus", "Belarusian"]),
        "BE": Identity(iso3: "bel", aliases: ["Belgium", "Belgian"]),
        "BZ": Identity(iso3: "blz", aliases: ["Belize", "Belizean"]),
        "BJ": Identity(iso3: "ben", aliases: ["Benin", "Beninese"]),
        "BT": Identity(iso3: "btn", aliases: ["Bhutan", "Bhutanese"]),
        "BO": Identity(iso3: "bol", aliases: ["Bolivia", "Bolivian"]),
        "BA": Identity(iso3: "bih", aliases: ["Bosnia and Herzegovina", "Bosnian", "Herzegovinian"]),
        "BW": Identity(iso3: "bwa", aliases: ["Botswana", "Motswana"]),
        "BR": Identity(iso3: "bra", aliases: ["Brazil", "Brazilian"]),
        "BN": Identity(iso3: "brn", aliases: ["Brunei", "Bruneian"]),
        "BG": Identity(iso3: "bgr", aliases: ["Bulgaria", "Bulgarian"]),
        "BF": Identity(iso3: "bfa", aliases: ["Burkina Faso", "Burkinabe"]),
        "BI": Identity(iso3: "bdi", aliases: ["Burundi", "Burundian"]),
        "KH": Identity(iso3: "khm", aliases: ["Cambodia", "Cambodian"]),
        "CM": Identity(iso3: "cmr", aliases: ["Cameroon", "Cameroonian"]),
        "CA": Identity(iso3: "can", aliases: ["Canada", "Canadian"]),
        "CV": Identity(iso3: "cpv", aliases: ["Cape Verde", "Cape Verdian"]),
        "CF": Identity(iso3: "caf", aliases: ["Central African Republic", "Central African"]),
        "TD": Identity(iso3: "tcd", aliases: ["Chad", "Chadian"]),
        "CL": Identity(iso3: "chl", aliases: ["Chile", "Chilean"]),
        "CN": Identity(iso3: "chn", aliases: ["China", "Chinese"]),
        "CO": Identity(iso3: "col", aliases: ["Colombia", "Colombian"]),
        "KM": Identity(iso3: "com", aliases: ["Comoros", "Comoran"]),
        "CG": Identity(iso3: "cog", aliases: ["Republic of the Congo", "Congo-Brazzaville", "Brazzaville"]),
        "CR": Identity(iso3: "cri", aliases: ["Costa Rica", "Costa Rican"]),
        "HR": Identity(iso3: "hrv", aliases: ["Croatia", "Croatian"]),
        "CU": Identity(iso3: "cub", aliases: ["Cuba", "Cuban"]),
        "CY": Identity(iso3: "cyp", aliases: ["Cyprus", "Cypriot"]),
        "CZ": Identity(iso3: "cze", aliases: ["Czechia", "Czech Republic", "Czech"]),
        "CD": Identity(iso3: "cod", aliases: ["Democratic Republic of the Congo", "DR Congo", "Congo-Kinshasa", "Kinshasa"]),
        "DK": Identity(iso3: "dnk", aliases: ["Denmark", "Danish"]),
        "DJ": Identity(iso3: "dji", aliases: ["Djibouti"]),
        "DM": Identity(iso3: "dma", aliases: ["Dominica"]),
        "DO": Identity(iso3: "dom", aliases: ["Dominican Republic", "Santo Domingo"]),
        "EC": Identity(iso3: "ecu", aliases: ["Ecuador", "Ecuadorean"]),
        "EG": Identity(iso3: "egy", aliases: ["Egypt", "Egyptian"]),
        "SV": Identity(iso3: "slv", aliases: ["El Salvador", "Salvadoran"]),
        "GQ": Identity(iso3: "gnq", aliases: ["Equatorial Guinea", "Equatorial Guinean"]),
        "ER": Identity(iso3: "eri", aliases: ["Eritrea", "Eritrean"]),
        "EE": Identity(iso3: "est", aliases: ["Estonia", "Estonian"]),
        "SZ": Identity(iso3: "swz", aliases: ["Eswatini", "Swaziland", "Swazi"]),
        "ET": Identity(iso3: "eth", aliases: ["Ethiopia", "Ethiopian"]),
        "FJ": Identity(iso3: "fji", aliases: ["Fiji", "Fijian"]),
        "FI": Identity(iso3: "fin", aliases: ["Finland", "Finnish"]),
        "FR": Identity(iso3: "fra", aliases: ["France", "French"]),
        "GA": Identity(iso3: "gab", aliases: ["Gabon", "Gabonese"]),
        "GM": Identity(iso3: "gmb", aliases: ["Gambia", "Gambian"]),
        "GE": Identity(iso3: "geo", aliases: ["Georgian", "Georgia (country)", "Tbilisi"]),
        "DE": Identity(iso3: "deu", aliases: ["Germany", "German"]),
        "GH": Identity(iso3: "gha", aliases: ["Ghana", "Ghanaian"]),
        "GR": Identity(iso3: "grc", aliases: ["Greece", "Greek"]),
        "GD": Identity(iso3: "grd", aliases: ["Grenada", "Grenadian"]),
        "GT": Identity(iso3: "gtm", aliases: ["Guatemala", "Guatemalan"]),
        "GN": Identity(iso3: "gin", aliases: ["Guinea", "Guinean"]),
        "GW": Identity(iso3: "gnb", aliases: ["Guinea-Bissau", "Guinea-Bissauan"]),
        "GY": Identity(iso3: "guy", aliases: ["Guyana", "Guyanese"]),
        "HT": Identity(iso3: "hti", aliases: ["Haiti", "Haitian"]),
        "HN": Identity(iso3: "hnd", aliases: ["Honduras", "Honduran"]),
        "HU": Identity(iso3: "hun", aliases: ["Hungary", "Hungarian"]),
        "IS": Identity(iso3: "isl", aliases: ["Iceland", "Icelander"]),
        "IN": Identity(iso3: "ind", aliases: ["India", "Indian"]),
        "ID": Identity(iso3: "idn", aliases: ["Indonesia", "Indonesian"]),
        "IR": Identity(iso3: "irn", aliases: ["Iran", "Iranian"]),
        "IQ": Identity(iso3: "irq", aliases: ["Iraq", "Iraqi"]),
        "IE": Identity(iso3: "irl", aliases: ["Ireland", "Irish"]),
        "IL": Identity(iso3: "isr", aliases: ["Israel", "Israeli"]),
        "IT": Identity(iso3: "ita", aliases: ["Italy", "Italian"]),
        "CI": Identity(iso3: "civ", aliases: ["Côte d’Ivoire", "Côte d'Ivoire", "Ivory Coast", "Ivorian"]),
        "JM": Identity(iso3: "jam", aliases: ["Jamaica", "Jamaican"]),
        "JP": Identity(iso3: "jpn", aliases: ["Japan", "Japanese"]),
        "JO": Identity(iso3: "jor", aliases: ["Jordan", "Jordanian"]),
        "KZ": Identity(iso3: "kaz", aliases: ["Kazakhstan", "Kazakhstani"]),
        "KE": Identity(iso3: "ken", aliases: ["Kenya", "Kenyan"]),
        "KI": Identity(iso3: "kir", aliases: ["Kiribati", "I-Kiribati"]),
        "KW": Identity(iso3: "kwt", aliases: ["Kuwait", "Kuwaiti"]),
        "KG": Identity(iso3: "kgz", aliases: ["Kyrgyzstan", "Kirghiz"]),
        "LA": Identity(iso3: "lao", aliases: ["Laos", "Laotian"]),
        "LV": Identity(iso3: "lva", aliases: ["Latvia", "Latvian"]),
        "LB": Identity(iso3: "lbn", aliases: ["Lebanon", "Lebanese"]),
        "LS": Identity(iso3: "lso", aliases: ["Lesotho", "Mosotho"]),
        "LR": Identity(iso3: "lbr", aliases: ["Liberia", "Liberian"]),
        "LY": Identity(iso3: "lby", aliases: ["Libya", "Libyan"]),
        "LI": Identity(iso3: "lie", aliases: ["Liechtenstein", "Liechtensteiner"]),
        "LT": Identity(iso3: "ltu", aliases: ["Lithuania", "Lithuanian"]),
        "LU": Identity(iso3: "lux", aliases: ["Luxembourg", "Luxembourger"]),
        "MG": Identity(iso3: "mdg", aliases: ["Madagascar", "Malagasy"]),
        "MW": Identity(iso3: "mwi", aliases: ["Malawi", "Malawian"]),
        "MY": Identity(iso3: "mys", aliases: ["Malaysia", "Malaysian"]),
        "MV": Identity(iso3: "mdv", aliases: ["Maldives", "Maldivan"]),
        "ML": Identity(iso3: "mli", aliases: ["Mali", "Malian"]),
        "MT": Identity(iso3: "mlt", aliases: ["Malta", "Maltese"]),
        "MH": Identity(iso3: "mhl", aliases: ["Marshall Islands", "Marshallese"]),
        "MR": Identity(iso3: "mrt", aliases: ["Mauritania", "Mauritanian"]),
        "MU": Identity(iso3: "mus", aliases: ["Mauritius", "Mauritian"]),
        "MX": Identity(iso3: "mex", aliases: ["Mexico", "Mexican"]),
        "FM": Identity(iso3: "fsm", aliases: ["Micronesia", "Micronesian", "Pohnpei", "Chuuk", "Yap", "Kosrae"]),
        "MD": Identity(iso3: "mda", aliases: ["Moldova", "Moldovan"]),
        "MC": Identity(iso3: "mco", aliases: ["Monaco", "Monegasque"]),
        "MN": Identity(iso3: "mng", aliases: ["Mongolia", "Mongolian"]),
        "ME": Identity(iso3: "mne", aliases: ["Montenegro", "Montenegrin"]),
        "MA": Identity(iso3: "mar", aliases: ["Morocco", "Moroccan"]),
        "MZ": Identity(iso3: "moz", aliases: ["Mozambique", "Mozambican"]),
        "MM": Identity(iso3: "mmr", aliases: ["Myanmar", "Burmese"]),
        "NA": Identity(iso3: "nam", aliases: ["Namibia", "Namibian"]),
        "NR": Identity(iso3: "nru", aliases: ["Nauru", "Nauruan"]),
        "NP": Identity(iso3: "npl", aliases: ["Nepal", "Nepalese"]),
        "NL": Identity(iso3: "nld", aliases: ["Netherlands", "Dutch"]),
        "NZ": Identity(iso3: "nzl", aliases: ["New Zealand", "New Zealander"]),
        "NI": Identity(iso3: "nic", aliases: ["Nicaragua", "Nicaraguan"]),
        "NE": Identity(iso3: "ner", aliases: ["Niger", "Nigerien"]),
        "NG": Identity(iso3: "nga", aliases: ["Nigeria", "Nigerian"]),
        "KP": Identity(iso3: "prk", aliases: ["North Korea", "North Korean"]),
        "MK": Identity(iso3: "mkd", aliases: ["North Macedonia", "Macedonian"]),
        "NO": Identity(iso3: "nor", aliases: ["Norway", "Norwegian"]),
        "OM": Identity(iso3: "omn", aliases: ["Oman", "Omani"]),
        "PK": Identity(iso3: "pak", aliases: ["Pakistan", "Pakistani"]),
        "PW": Identity(iso3: "plw", aliases: ["Palau", "Palauan"]),
        "PS": Identity(iso3: "pse", aliases: ["Palestine", "Palestinian"]),
        "PA": Identity(iso3: "pan", aliases: ["Panama", "Panamanian"]),
        "PG": Identity(iso3: "png", aliases: ["Papua New Guinea", "Papua New Guinean"]),
        "PY": Identity(iso3: "pry", aliases: ["Paraguay", "Paraguayan"]),
        "PE": Identity(iso3: "per", aliases: ["Peru", "Peruvian"]),
        "PH": Identity(iso3: "phl", aliases: ["Philippines", "Filipino"]),
        "PL": Identity(iso3: "pol", aliases: ["Poland", "Polish"]),
        "PT": Identity(iso3: "prt", aliases: ["Portugal", "Portuguese"]),
        "QA": Identity(iso3: "qat", aliases: ["Qatar", "Qatari"]),
        "RO": Identity(iso3: "rou", aliases: ["Romania", "Romanian"]),
        "RU": Identity(iso3: "rus", aliases: ["Russia", "Russian"]),
        "RW": Identity(iso3: "rwa", aliases: ["Rwanda", "Rwandan"]),
        "KN": Identity(iso3: "kna", aliases: ["Saint Kitts and Nevis", "Kittitian", "Nevisian"]),
        "LC": Identity(iso3: "lca", aliases: ["Saint Lucia", "Saint Lucian"]),
        "VC": Identity(iso3: "vct", aliases: ["Saint Vincent and the Grenadines", "Saint Vincentian"]),
        "WS": Identity(iso3: "wsm", aliases: ["Samoa", "Samoan"]),
        "SM": Identity(iso3: "smr", aliases: ["San Marino", "Sammarinese"]),
        "SA": Identity(iso3: "sau", aliases: ["Saudi Arabia", "Saudi Arabian"]),
        "SN": Identity(iso3: "sen", aliases: ["Senegal", "Senegalese"]),
        "RS": Identity(iso3: "srb", aliases: ["Serbia", "Serbian"]),
        "SC": Identity(iso3: "syc", aliases: ["Seychelles", "Seychellois"]),
        "SL": Identity(iso3: "sle", aliases: ["Sierra Leone", "Sierra Leonean"]),
        "SG": Identity(iso3: "sgp", aliases: ["Singapore", "Singaporean"]),
        "SK": Identity(iso3: "svk", aliases: ["Slovakia", "Slovak"]),
        "SI": Identity(iso3: "svn", aliases: ["Slovenia", "Slovene"]),
        "SB": Identity(iso3: "slb", aliases: ["Solomon Islands", "Solomon Islander"]),
        "SO": Identity(iso3: "som", aliases: ["Somalia", "Somali"]),
        "ZA": Identity(iso3: "zaf", aliases: ["South Africa", "South African"]),
        "KR": Identity(iso3: "kor", aliases: ["South Korea", "South Korean", "Korean"]),
        "SS": Identity(iso3: "ssd", aliases: ["South Sudan", "South Sudanese"]),
        "ES": Identity(iso3: "esp", aliases: ["Spain", "Spanish"]),
        "LK": Identity(iso3: "lka", aliases: ["Sri Lanka", "Sri Lankan"]),
        "SD": Identity(iso3: "sdn", aliases: ["Sudan", "Sudanese"]),
        "SR": Identity(iso3: "sur", aliases: ["Suriname", "Surinamer"]),
        "SE": Identity(iso3: "swe", aliases: ["Sweden", "Swedish"]),
        "CH": Identity(iso3: "che", aliases: ["Switzerland", "Swiss"]),
        "SY": Identity(iso3: "syr", aliases: ["Syria", "Syrian"]),
        "ST": Identity(iso3: "stp", aliases: ["São Tomé and Príncipe", "Sao Tomean"]),
        "TJ": Identity(iso3: "tjk", aliases: ["Tajikistan", "Tadzhik"]),
        "TZ": Identity(iso3: "tza", aliases: ["Tanzania", "Tanzanian"]),
        "TH": Identity(iso3: "tha", aliases: ["Thailand", "Thai"]),
        "TL": Identity(iso3: "tls", aliases: ["Timor-Leste", "East Timor", "Timorese"]),
        "TG": Identity(iso3: "tgo", aliases: ["Togo", "Togolese"]),
        "TO": Identity(iso3: "ton", aliases: ["Tonga", "Tongan"]),
        "TT": Identity(iso3: "tto", aliases: ["Trinidad and Tobago", "Trinidadian"]),
        "TN": Identity(iso3: "tun", aliases: ["Tunisia", "Tunisian"]),
        "TM": Identity(iso3: "tkm", aliases: ["Turkmenistan", "Turkmen"]),
        "TV": Identity(iso3: "tuv", aliases: ["Tuvalu", "Tuvaluan"]),
        "TR": Identity(iso3: "tur", aliases: ["Turkey", "Turkish", "Türkiye"]),
        "UG": Identity(iso3: "uga", aliases: ["Uganda", "Ugandan"]),
        "UA": Identity(iso3: "ukr", aliases: ["Ukraine", "Ukrainian"]),
        "AE": Identity(iso3: "are", aliases: ["United Arab Emirates", "Emirati"]),
        "GB": Identity(iso3: "gbr", aliases: ["United Kingdom", "British", "England", "English", "Scotland", "Scottish", "Welsh", "Wales", "Northern Ireland"]),
        "US": Identity(iso3: "usa", aliases: ["United States", "American", "U.S."]),
        "UY": Identity(iso3: "ury", aliases: ["Uruguay", "Uruguayan"]),
        "UZ": Identity(iso3: "uzb", aliases: ["Uzbekistan", "Uzbekistani"]),
        "VU": Identity(iso3: "vut", aliases: ["Vanuatu", "Ni-Vanuatu"]),
        "VA": Identity(iso3: "vat", aliases: ["Vatican", "Holy See"]),
        "VE": Identity(iso3: "ven", aliases: ["Venezuela", "Venezuelan"]),
        "VN": Identity(iso3: "vnm", aliases: ["Vietnam", "Vietnamese"]),
        "YE": Identity(iso3: "yem", aliases: ["Yemen", "Yemeni"]),
        "ZM": Identity(iso3: "zmb", aliases: ["Zambia", "Zambian"]),
        "ZW": Identity(iso3: "zwe", aliases: ["Zimbabwe", "Zimbabwean"]),
    ]
}
