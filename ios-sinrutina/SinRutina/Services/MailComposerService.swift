import MessageUI
import SwiftUI

/// Opens Apple Mail's composer already filled in.
///
/// SinRutina prepares; the person sends. There is no code path in this app that
/// sends an email without the system composer appearing first.
struct MailComposerView: UIViewControllerRepresentable {
    struct Draft {
        var recipients: [String]
        var subject: String
        var body: String
        /// App-group file names to attach.
        var attachmentNames: [String]

        init(
            recipients: [String] = [],
            subject: String = "",
            body: String = "",
            attachmentNames: [String] = []
        ) {
            self.recipients = recipients
            self.subject = subject
            self.body = body
            self.attachmentNames = attachmentNames
        }
    }

    let draft: Draft
    let onFinish: (MFMailComposeResult) -> Void

    static var canSendMail: Bool { MFMailComposeViewController.canSendMail() }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        if !draft.recipients.isEmpty {
            controller.setToRecipients(draft.recipients)
        }
        controller.setSubject(draft.subject)
        controller.setMessageBody(draft.body, isHTML: false)
        for name in draft.attachmentNames {
            guard let data = AttachmentStore.data(for: name) else { continue }
            controller.addAttachmentData(
                data,
                mimeType: AttachmentStore.mimeType(for: name),
                fileName: name
            )
        }
        return controller
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (MFMailComposeResult) -> Void

        init(onFinish: @escaping (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            let outcome = result
            Task { @MainActor in
                controller.dismiss(animated: true)
                self.onFinish(outcome)
            }
        }
    }
}

/// Fallback path when Mail is not configured: a `mailto:` link the system routes
/// to whatever mail client the person actually uses. Attachments are not possible
/// this way, and the UI says so instead of pretending.
@MainActor
enum MailFallback {
    static func url(for draft: MailComposerView.Draft) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = draft.recipients.joined(separator: ",")
        var items: [URLQueryItem] = []
        if !draft.subject.isEmpty { items.append(URLQueryItem(name: "subject", value: draft.subject)) }
        if !draft.body.isEmpty { items.append(URLQueryItem(name: "body", value: draft.body)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url
    }
}
