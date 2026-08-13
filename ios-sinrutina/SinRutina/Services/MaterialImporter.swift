import Foundation
import PDFKit

/// Turns files, pages and pasted text into study material, extracting plain text
/// locally so explanations never need the network.
nonisolated enum MaterialImporter {
    /// Characters kept per document. Enough to reason with, small enough to keep
    /// the local store light.
    private static let textLimit = 60_000

    // MARK: - Files

    static func material(fromFile url: URL, taskID: UUID?) throws -> StudyMaterialDraft {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let fileName = try AttachmentStore.store(from: url)
        let title = url.deletingPathExtension().lastPathComponent
        let extensionValue = url.pathExtension.lowercased()

        if extensionValue == "pdf" {
            let text = pdfText(at: AttachmentStore.url(for: fileName) ?? url)
            return StudyMaterialDraft(
                title: title,
                text: text,
                kind: .pdf,
                fileName: fileName,
                taskID: taskID
            )
        }

        if ["txt", "md", "markdown", "rtf", "csv", "json"].contains(extensionValue) {
            let text = plainText(at: AttachmentStore.url(for: fileName) ?? url)
            return StudyMaterialDraft(
                title: title,
                text: text,
                kind: extensionValue == "txt" || extensionValue == "md" ? .text : .document,
                fileName: fileName,
                taskID: taskID
            )
        }

        return StudyMaterialDraft(
            title: title,
            text: "",
            kind: .sharedFile,
            fileName: fileName,
            taskID: taskID
        )
    }

    // MARK: - Web pages

    /// Downloads a page and keeps only its readable text. Only the address the
    /// person handed over is requested.
    static func material(fromWebPage url: URL, taskID: UUID?) async throws -> StudyMaterialDraft {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AttachmentError.unreadable
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let text = readableText(fromHTML: html)
        let title = pageTitle(fromHTML: html) ?? (url.host ?? "Página web")
        return StudyMaterialDraft(
            title: title,
            text: text,
            kind: .webPage,
            sourceURLString: url.absoluteString,
            taskID: taskID
        )
    }

    // MARK: - Plain text

    static func material(fromText text: String, title: String?, taskID: UUID?) -> StudyMaterialDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return StudyMaterialDraft(
            title: title?.isEmpty == false ? title! : SRHeuristics.shortTitle(from: trimmed),
            text: String(trimmed.prefix(textLimit)),
            kind: .note,
            taskID: taskID
        )
    }

    // MARK: - Extraction

    static func pdfText(at url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var output = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            output += pageText
            output += "\n"
            if output.count > textLimit { break }
        }
        return String(output.prefix(textLimit))
    }

    static func plainText(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return String(text.prefix(textLimit))
    }

    /// Very small HTML reader: strips script, style and tags. Good enough for
    /// articles and far cheaper than a parser dependency.
    static func readableText(fromHTML html: String) -> String {
        var value = html
        for tag in ["script", "style", "nav", "footer", "header", "noscript", "svg"] {
            value = value.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        value = value.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "</p>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        value = value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        value = value.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(textLimit))
    }

    static func pageTitle(fromHTML html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>[\\s\\S]*?</title>", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let raw = String(html[range])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : String(raw.prefix(90))
    }
}

/// A material about to be created. Kept separate from the SwiftData model so
/// importing can happen off the main actor without touching the store.
nonisolated struct StudyMaterialDraft: Sendable {
    var title: String
    var text: String
    var kind: StudyMaterial.Kind
    var sourceURLString: String?
    var fileName: String?
    var taskID: UUID?

    init(
        title: String,
        text: String,
        kind: StudyMaterial.Kind,
        sourceURLString: String? = nil,
        fileName: String? = nil,
        taskID: UUID? = nil
    ) {
        self.title = title.isEmpty ? "Material" : title
        self.text = text
        self.kind = kind
        self.sourceURLString = sourceURLString
        self.fileName = fileName
        self.taskID = taskID
    }

    func makeMaterial() -> StudyMaterial {
        StudyMaterial(
            title: title,
            text: text,
            kind: kind,
            sourceURLString: sourceURLString,
            fileName: fileName,
            taskID: taskID
        )
    }
}
