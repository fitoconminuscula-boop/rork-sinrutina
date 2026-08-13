import Foundation
import SwiftData

/// A piece of material attached to a study task: a PDF, a page, notes or plain
/// text. Text lives here so an explanation never needs the network.
@Model
final class StudyMaterial {
    var id: UUID
    var title: String
    /// Extracted plain text, bounded so the store stays small.
    var text: String
    var kindRaw: String
    /// Original web address, when the material came from a page.
    var sourceURLString: String?
    /// File name inside the app group container, when a real file was imported.
    var fileName: String?
    var addedAt: Date
    var lastOpenedAt: Date?
    /// Identifier of the task this belongs to. Kept as a plain value so the
    /// material survives even if the task is reshaped.
    var taskID: UUID?
    /// Page or section the person stopped at, in their own words.
    var progressNote: String?

    var kind: Kind {
        get { Kind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    nonisolated enum Kind: String, Codable, CaseIterable, Sendable {
        case pdf
        case text
        case document
        case webPage
        case note
        case sharedFile

        var label: String {
            switch self {
            case .pdf: return "PDF"
            case .text: return "Texto"
            case .document: return "Documento"
            case .webPage: return "Página web"
            case .note: return "Nota"
            case .sharedFile: return "Archivo"
            }
        }

        var symbolName: String {
            switch self {
            case .pdf: return "doc.richtext"
            case .text: return "text.alignleft"
            case .document: return "doc"
            case .webPage: return "safari"
            case .note: return "note.text"
            case .sharedFile: return "paperclip"
            }
        }
    }

    init(
        title: String,
        text: String = "",
        kind: Kind = .text,
        sourceURLString: String? = nil,
        fileName: String? = nil,
        taskID: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.text = String(text.prefix(60_000))
        self.kindRaw = kind.rawValue
        self.sourceURLString = sourceURLString
        self.fileName = fileName
        self.addedAt = Date()
        self.lastOpenedAt = nil
        self.taskID = taskID
        self.progressNote = nil
    }

    /// Rough reading time, used to propose sessions that actually fit.
    var estimatedReadingMinutes: Int {
        let words = text.split(whereSeparator: { $0 == " " || $0.isNewline }).count
        guard words > 0 else { return 10 }
        return max(2, min(240, Int(Double(words) / 180.0)))
    }

    var hasText: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).count > 40 }

    var subtitle: String {
        var parts: [String] = [kind.label]
        if hasText { parts.append("\(estimatedReadingMinutes) min de lectura") }
        if let progressNote, !progressNote.isEmpty { parts.append(progressNote) }
        return parts.joined(separator: " · ")
    }

    /// A bounded fragment handed to the model: never the whole document.
    func fragment(around query: String? = nil, limit: Int = 1_600) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        guard let query, query.count >= 4,
              let range = clean.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(clean.prefix(limit))
        }
        let start = clean.index(range.lowerBound, offsetBy: -min(limit / 2, clean.distance(from: clean.startIndex, to: range.lowerBound)))
        let remaining = clean.distance(from: start, to: clean.endIndex)
        let end = clean.index(start, offsetBy: min(limit, remaining))
        return String(clean[start..<end])
    }
}
