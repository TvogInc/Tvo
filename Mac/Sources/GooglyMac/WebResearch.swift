import Foundation

/// A short researched answer: a title, up to four paragraphs, and where it came from.
struct ResearchReport {
    var question: String
    var title: String
    var paragraphs: [String]
    var sources: [(title: String, url: URL)]

    /// Plain text, for him (and the phone's saved transcript).
    var plainText: String {
        ([title] + paragraphs).joined(separator: "\n\n")
    }
}

/// Searches the web without a paid search API, then uses Gemini to summarize the results.
enum WebResearch {
    static let model = "gemini-3.8-flash"
    private static let summaryModels = [model, "gemini-3.5-flash-lite"]
    private static let maxSummaryResults = 5
    private static let maxSnippetCharacters = 400
    private static let maxContextCharacters = 600
    private static let maxSummaryTokens = 350

    enum ResearchError: LocalizedError {
        case noKey, failed(String), rateLimited, retryWithAnotherModel(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "I need a Gemini API key for research. Add one under Gemini API Key in the menu bar."
            case .failed(let why): return "The research didn't come back: \(why.prefix(240))"
            case .rateLimited: return "Gemini is rate-limited right now, so Tvo couldn't summarize the web results. Try again later."
            case .retryWithAnotherModel(let why): return "Gemini couldn't summarize the web results: \(why.prefix(200))"
            }
        }
    }

    static func research(_ question: String, context: String?) async throws -> ResearchReport {
        guard let key = Keychain.get(.gemini) else { throw ResearchError.noKey }
        let results = try await search(question)
        guard !results.isEmpty else { throw ResearchError.failed("DuckDuckGo returned no web results.") }
        let selectedResults = Array(results.prefix(maxSummaryResults))
        let sources = selectedResults.map { ($0.title, $0.url) }
        var lastTemporaryError: ResearchError?

        for summaryModel in summaryModels {
            do {
                return try await summarize(
                    question,
                    context: context,
                    results: selectedResults,
                    key: key,
                    model: summaryModel,
                    sources: sources
                )
            } catch ResearchError.rateLimited {
                lastTemporaryError = .rateLimited
                continue
            } catch let error as ResearchError {
                if case .retryWithAnotherModel = error {
                    lastTemporaryError = error
                    continue
                }
                throw error
            } catch {
                throw error
            }
        }
        if let lastTemporaryError { throw lastTemporaryError }
        throw ResearchError.failed("Gemini couldn't summarize the web results.")
    }

    private struct SearchResult {
        var title: String
        var snippet: String
        var url: URL
    }

    private static func search(_ query: String) async throws -> [SearchResult] {
        guard let url = URL(string: "https://html.duckduckgo.com/html/") else {
            throw ResearchError.failed("invalid web search endpoint")
        }
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Tvo/1.0 (macOS web research)", forHTTPHeaderField: "User-Agent")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResearchError.failed("DuckDuckGo returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 429 {
                throw ResearchError.failed("DuckDuckGo search is temporarily rate-limited (HTTP 429). Try again soon.")
            }
            throw ResearchError.failed("DuckDuckGo search failed (HTTP \(http.statusCode)).")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw ResearchError.failed("DuckDuckGo returned invalid text.")
        }
        return parseResults(html)
    }

    private static func parseResults(_ html: String) -> [SearchResult] {
        guard let anchorRegex = try? NSRegularExpression(pattern: #"(?is)<a\b([^>]*)>(.*?)</a>"#),
              let attributeRegex = try? NSRegularExpression(pattern: #"(?i)\b(href|class)\s*=\s*["']([^"']*)["']"#),
              let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else { return [] }
        let source = html as NSString
        let range = NSRange(location: 0, length: source.length)
        var titles: [(url: URL, title: String)] = []
        var snippets: [String: String] = [:]

        for match in anchorRegex.matches(in: html, range: range) {
            let attributes = source.substring(with: match.range(at: 1))
            let content = source.substring(with: match.range(at: 2))
            let attrSource = attributes as NSString
            let attrRange = NSRange(location: 0, length: attrSource.length)
            var href: String?
            var className: String?
            for attribute in attributeRegex.matches(in: attributes, range: attrRange) {
                let name = attrSource.substring(with: attribute.range(at: 1)).lowercased()
                let value = attrSource.substring(with: attribute.range(at: 2))
                if name == "href" { href = value }
                if name == "class" { className = value }
            }
            guard let className,
                  className.contains("result__a") || className.contains("result__snippet"),
                  let href, let url = URL(string: href),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, !host.isEmpty else { continue }

            let contentRange = NSRange(location: 0, length: (content as NSString).length)
            let plainText = tagRegex.stringByReplacingMatches(
                in: content,
                range: contentRange,
                withTemplate: " "
            )
            let text = decodeHTML(plainText)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !text.isEmpty else { continue }
            if className.contains("result__a") {
                titles.append((url, text))
            } else {
                snippets[url.absoluteString] = text
            }
        }

        var seen = Set<String>()
        return titles.compactMap { result in
            guard seen.insert(result.url.absoluteString).inserted else { return nil }
            return SearchResult(
                title: result.title,
                snippet: snippets[result.url.absoluteString] ?? result.title,
                url: result.url
            )
        }
    }

    private static func decodeHTML(_ value: String) -> String {
        var decoded = value
        for (entity, character) in [
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
            ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "),
            ("&amp;", "&")
        ] {
            decoded = decoded.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        return decoded
    }

    private static func summarize(
        _ question: String,
        context: String?,
        results: [SearchResult],
        key: String,
        model: String,
        sources: [(title: String, url: URL)]
    ) async throws -> ResearchReport {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw ResearchError.failed("invalid Gemini endpoint")
        }
        components.queryItems = [URLQueryItem(name: "key", value: key)]
        guard let url = components.url else { throw ResearchError.failed("invalid research URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var input = question
        if let context, !context.isEmpty {
            let briefContext = String(context.prefix(maxContextCharacters))
            input += "\n\nRelevant screen context: \(briefContext)"
        }
        input += "\n\nWeb search results:\n" + results.map {
            let snippet = String($0.snippet.prefix(maxSnippetCharacters))
            return "Title: \($0.title)\nSnippet: \(snippet)"
        }.joined(separator: "\n\n")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "systemInstruction": ["parts": [["text": """
            Summarize only the supplied web search results for a busy person. \
            First line: a plain title of under eight words. Then up to three short sentences with the direct answer. \
            Do not search the web or invent facts missing from the snippets. Plain text only: no markdown, \
            no headings, no bullet lists, and no links in the text.
            """]]],
            "contents": [["role": "user", "parts": [["text": input]]]],
            "generationConfig": ["maxOutputTokens": maxSummaryTokens],
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut || error.code == .networkConnectionLost {
            throw ResearchError.retryWithAnotherModel(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ResearchError.failed("Gemini returned a non-HTTP response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let details = Self.apiError(data: data)
            if httpResponse.statusCode == 429 { throw ResearchError.rateLimited }
            if (500...599).contains(httpResponse.statusCode) {
                throw ResearchError.retryWithAnotherModel(Self.failureMessage(statusCode: httpResponse.statusCode, details: details))
            }
            throw ResearchError.failed(Self.failureMessage(statusCode: httpResponse.statusCode, details: details))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidate = (json["candidates"] as? [[String: Any]])?.first,
              let content = candidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw ResearchError.failed("Gemini returned an invalid research response.")
        }

        var text = parts.compactMap { $0["text"] as? String }.joined()
        text = text.replacingOccurrences(of: #"\s*\(\[[^\]]*\]\([^)]*\)\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s*\[https?://[^\]]*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "")
        let blocks = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let title = blocks.first else { throw ResearchError.failed("empty answer") }
        return ResearchReport(question: question, title: title, paragraphs: Array(blocks.dropFirst().prefix(4)),
                              sources: sources)
    }

    private struct APIError {
        var status: String?
        var message: String?
        var quotaDetails: String
    }

    private static func apiError(data: Data) -> APIError {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = root?["error"] as? [String: Any]
        let details = error?["details"] as? [[String: Any]] ?? []
        let quotaDetails = details
            .filter { ($0["@type"] as? String)?.hasSuffix("google.rpc.QuotaFailure") == true }
            .map { String(describing: $0) }
            .joined(separator: " ")
        return APIError(
            status: error?["status"] as? String,
            message: error?["message"] as? String,
            quotaDetails: quotaDetails
        )
    }

    private static func isDailyQuota(_ error: APIError) -> Bool {
        let detail = "\(error.status ?? "") \(error.message ?? "") \(error.quotaDetails)".lowercased()
        return detail.contains("perday") || detail.contains("per_day")
            || detail.contains("per day") || detail.contains("daily quota")
    }

    private static func failureMessage(statusCode: Int, details: APIError) -> String {
        let message = details.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if statusCode == 429 {
            if isDailyQuota(details) {
                return "Gemini's daily research quota appears exhausted (HTTP 429). Wait for it to reset or check your project limits in Google AI Studio."
            }
            return "Gemini rate-limited research (HTTP 429). Tvo retried briefly; wait a little and check your Gemini API usage and limits in Google AI Studio."
        }
        let explanation = message.flatMap { $0.isEmpty ? nil : ": \($0.prefix(180))" } ?? ""
        return "Gemini research request failed (HTTP \(statusCode))\(explanation)"
    }
}
