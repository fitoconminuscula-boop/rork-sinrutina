import Foundation

/// The only part of SinRutina that talks to the internet.
///
/// Rules it enforces on itself:
/// 1. It never receives a document. Callers hand it a short query and, at most,
///    a handful of keywords.
/// 2. It prefers scholarship over SEO: scientific articles and repositories are
///    asked first, general search only fills the gaps.
/// 3. It returns links and short snippets, never scraped pages.
actor WebSearchTool {
    static let shared = WebSearchTool()

    /// The exact strings that left the device, so the UI can show them verbatim.
    private(set) var lastSentQuery: String?

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: configuration)
    }

    // MARK: - Public surface

    /// Runs a search across the tiers that make sense for the request.
    /// - Parameters:
    ///   - query: a short question. Must not contain the person's document.
    ///   - academicFirst: true for study work, false for everyday facts.
    func search(query: String, academicFirst: Bool = true, limit: Int = 6) async -> [SRWebSource] {
        let clean = Self.sanitize(query)
        guard clean.count >= 3 else { return [] }
        lastSentQuery = clean

        var results: [SRWebSource] = []
        if academicFirst {
            results += await scholarlyResults(query: clean)
        }
        results += await encyclopedicResults(query: clean)
        if results.count < limit {
            results += await generalResults(query: clean)
        }

        // Deduplicate by host + title, then order by authority tier.
        var seen = Set<String>()
        let unique = results.filter { source in
            let key = "\(source.host)|\(source.title.lowercased())"
            return seen.insert(key).inserted
        }
        return Array(
            unique
                .sorted { lhs, rhs in
                    if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
                    return (lhs.year ?? 0) > (rhs.year ?? 0)
                }
                .prefix(limit)
        )
    }

    /// Strips anything that looks personal before a string may leave the device.
    /// The rules themselves live in `SRQueryGuard`, shared with the intents.
    nonisolated static func sanitize(_ raw: String) -> String {
        SRQueryGuard.sanitize(raw)
    }

    // MARK: - Tier 1: scholarship (OpenAlex)

    private func scholarlyResults(query: String) async -> [SRWebSource] {
        guard var components = URLComponents(string: "https://api.openalex.org/works") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per-page", value: "5"),
            URLQueryItem(name: "select", value: "id,title,publication_year,primary_location,authorships,doi,type")
        ]
        guard let url = components.url,
              let payload: OpenAlexResponse = await fetch(url) else { return [] }

        return payload.results.compactMap { work -> SRWebSource? in
            guard let title = work.title, !title.isEmpty else { return nil }
            let link = work.doi ?? work.primary_location?.landing_page_url ?? work.id
            guard let link, let parsed = URL(string: link) else { return nil }
            let host = parsed.host ?? "openalex.org"
            let venue = work.primary_location?.source?.display_name
            let authors = work.authorships?
                .prefix(2)
                .compactMap { $0.author?.display_name }
                .joined(separator: ", ")
            return SRWebSource(
                id: link,
                title: title,
                snippet: venue ?? "Artículo indexado en OpenAlex",
                urlString: link,
                tier: work.type == "book" || work.type == "book-chapter" ? .primarySource : .scientificArticle,
                host: host,
                year: work.publication_year,
                authors: (authors?.isEmpty ?? true) ? nil : authors
            )
        }
    }

    // MARK: - Tier 2: encyclopedic (Wikipedia, Spanish first)

    private func encyclopedicResults(query: String) async -> [SRWebSource] {
        guard var components = URLComponents(string: "https://es.wikipedia.org/w/api.php") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query),
            URLQueryItem(name: "srlimit", value: "3"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "origin", value: "*")
        ]
        guard let url = components.url,
              let payload: WikipediaResponse = await fetch(url) else { return [] }

        return payload.query.search.compactMap { hit in
            let slug = hit.title.replacingOccurrences(of: " ", with: "_")
            guard let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let link = URL(string: "https://es.wikipedia.org/wiki/\(encoded)") else { return nil }
            return SRWebSource(
                id: link.absoluteString,
                title: hit.title,
                snippet: hit.snippet.srStrippingHTML,
                urlString: link.absoluteString,
                tier: .qualitySecondary,
                host: "es.wikipedia.org",
                year: nil,
                authors: nil
            )
        }
    }

    // MARK: - Tier 3: general (DuckDuckGo instant answers)

    private func generalResults(query: String) async -> [SRWebSource] {
        guard var components = URLComponents(string: "https://api.duckduckgo.com/") else { return [] }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        guard let url = components.url,
              let payload: DuckDuckGoResponse = await fetch(url) else { return [] }

        var results: [SRWebSource] = []
        if let abstract = payload.AbstractText, !abstract.isEmpty,
           let link = payload.AbstractURL, let parsed = URL(string: link) {
            results.append(
                SRWebSource(
                    id: link,
                    title: payload.Heading ?? query,
                    snippet: abstract,
                    urlString: link,
                    tier: Self.tier(forHost: parsed.host ?? ""),
                    host: parsed.host ?? "",
                    year: nil,
                    authors: payload.AbstractSource
                )
            )
        }
        for topic in payload.RelatedTopics?.prefix(4) ?? [] {
            guard let text = topic.Text, !text.isEmpty,
                  let link = topic.FirstURL, let parsed = URL(string: link) else { continue }
            let host = parsed.host ?? ""
            results.append(
                SRWebSource(
                    id: link,
                    title: String(text.prefix(90)),
                    snippet: text,
                    urlString: link,
                    tier: Self.tier(forHost: host),
                    host: host,
                    year: nil,
                    authors: nil
                )
            )
        }
        return results
    }

    // MARK: - Authority

    /// Maps a host to the hierarchy the annex asks for. Unknown SEO-ish hosts land
    /// at the bottom, so they only appear when nothing better exists.
    nonisolated static func tier(forHost host: String) -> SRSourceTier {
        let lower = host.lowercased()
        if lower.contains("doi.org") || lower.contains("arxiv.org") || lower.contains("pubmed")
            || lower.contains("ncbi.nlm.nih.gov") || lower.contains("sciencedirect")
            || lower.contains("springer") || lower.contains("wiley") || lower.contains("jstor")
            || lower.contains("tandfonline") || lower.contains("sagepub") || lower.contains("nature.com")
            || lower.contains("plos.org") || lower.contains("scielo") {
            return .scientificArticle
        }
        if lower.contains("gutenberg.org") || lower.contains("archive.org")
            || lower.contains("bne.es") || lower.contains("loc.gov") {
            return .primarySource
        }
        if lower.hasSuffix(".edu") || lower.contains(".edu.") || lower.contains(".ac.")
            || lower.contains("universi") || lower.contains("uned.es") || lower.contains("csic.es") {
            return .university
        }
        if lower.contains("dialnet") || lower.contains("redalyc") || lower.contains("zenodo")
            || lower.contains("core.ac.uk") || lower.contains("repositor") || lower.contains("hal.science") {
            return .academicRepository
        }
        if lower.hasSuffix(".gov") || lower.contains(".gob.") || lower.hasSuffix(".gob.es")
            || lower.contains("europa.eu") || lower.contains("who.int") || lower.contains("un.org")
            || lower.contains("boe.es") || lower.contains("ine.es") {
            return .officialBody
        }
        if lower.contains("developer.") || lower.contains("docs.") || lower.contains("developer.apple.com")
            || lower.contains("mdn") || lower.contains("readthedocs") {
            return .technicalDocs
        }
        if lower.contains("wikipedia.org") || lower.contains("britannica")
            || lower.contains("stanford.edu") || lower.contains("plato.stanford.edu") {
            return .qualitySecondary
        }
        return .other
    }

    // MARK: - Transport

    private func fetch<T: Decodable>(_ url: URL) async -> T? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Only the failing host is logged, never the query.
            print("[SinRutina] Búsqueda web sin respuesta de \(url.host ?? "desconocido"): \(type(of: error))")
            return nil
        }
    }
}

// MARK: - Wire formats

private nonisolated struct OpenAlexResponse: Decodable {
    struct Work: Decodable {
        struct Location: Decodable {
            struct Source: Decodable {
                let display_name: String?
            }
            let landing_page_url: String?
            let source: Source?
        }
        struct Authorship: Decodable {
            struct Author: Decodable {
                let display_name: String?
            }
            let author: Author?
        }

        let id: String?
        let title: String?
        let publication_year: Int?
        let primary_location: Location?
        let authorships: [Authorship]?
        let doi: String?
        let type: String?
    }

    let results: [Work]
}

private nonisolated struct WikipediaResponse: Decodable {
    struct Query: Decodable {
        struct Hit: Decodable {
            let title: String
            let snippet: String
        }
        let search: [Hit]
    }
    let query: Query
}

private nonisolated struct DuckDuckGoResponse: Decodable {
    struct Topic: Decodable {
        let Text: String?
        let FirstURL: String?
    }
    let Heading: String?
    let AbstractText: String?
    let AbstractURL: String?
    let AbstractSource: String?
    let RelatedTopics: [Topic]?
}

private nonisolated extension String {
    /// Wikipedia snippets arrive with markup around the matched words.
    var srStrippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
