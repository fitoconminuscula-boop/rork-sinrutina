import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Adds material to a study task: a file, a page or plain text.
///
/// Everything is read on device. A page is the only thing that touches the
/// network, and it only requests the address the person typed.
struct MaterialImportSheet: View {
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var mode: Mode = .file
    @State private var urlText = ""
    @State private var noteText = ""
    @State private var noteTitle = ""
    @State private var showsFileImporter = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private enum Mode: String, CaseIterable, Identifiable {
        case file
        case page
        case text

        var id: String { rawValue }

        var label: String {
            switch self {
            case .file: return "Archivo"
            case .page: return "Página"
            case .text: return "Texto"
            }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Añadir material")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SRDesign.ink)
                    .padding(.top, 22)

                Picker("Tipo", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .file:
                    filePane
                case .page:
                    pagePane
                case .text:
                    textPane
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.blush)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label(
                    "El texto se extrae aquí dentro. Nada se sube a ningún servidor.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 36)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf, .text, .item],
            allowsMultipleSelection: false
        ) { result in
            handleFileResult(result)
        }
    }

    // MARK: - Panes

    private var filePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PDF, apuntes, documentos o cualquier archivo que quieras tener a mano.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showsFileImporter = true
                SRHaptics.light()
            } label: {
                Label("Elegir archivo", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .disabled(isWorking)
        }
    }

    private var pagePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("https://…", text: $urlText)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.body)
                .padding(14)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))

            Text("Se guarda el texto legible de la página para poder estudiarla sin conexión.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)

            Button {
                Task { await importPage() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Guardar página")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .disabled(isWorking || URL(string: urlText.trimmingCharacters(in: .whitespaces))?.host == nil)
        }
    }

    private var textPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Título (opcional)", text: $noteTitle)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))

            TextField("Pega aquí el texto o escribe tus apuntes", text: $noteText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .frame(minHeight: 160, alignment: .topLeading)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))

            Button("Guardar texto") { importText() }
                .buttonStyle(SRPrimaryButtonStyle())
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).count < 20)
        }
    }

    // MARK: - Importing

    private func handleFileResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            isWorking = true
            errorMessage = nil
            Task {
                do {
                    let draft = try MaterialImporter.material(fromFile: url, taskID: task.id)
                    await MainActor.run { finish(with: draft, attachFileName: draft.fileName) }
                } catch {
                    await MainActor.run {
                        isWorking = false
                        errorMessage = "No pudimos leer ese archivo."
                    }
                }
            }
        case .failure:
            errorMessage = "No pudimos abrir el selector de archivos."
        }
    }

    private func importPage() async {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)) else { return }
        isWorking = true
        errorMessage = nil
        do {
            let draft = try await MaterialImporter.material(fromWebPage: url, taskID: task.id)
            guard draft.text.count > 60 else {
                isWorking = false
                errorMessage = "Esa página no dejó texto legible."
                return
            }
            finish(with: draft, attachFileName: nil)
        } catch {
            isWorking = false
            errorMessage = "No pudimos leer esa página."
        }
    }

    private func importText() {
        let draft = MaterialImporter.material(
            fromText: noteText,
            title: noteTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            taskID: task.id
        )
        finish(with: draft, attachFileName: nil)
    }

    private func finish(with draft: StudyMaterialDraft, attachFileName: String?) {
        let material = draft.makeMaterial()
        modelContext.insert(material)

        // A file the person imported is also an attachment of the task, so the mail
        // composer can offer it later.
        if let attachFileName {
            var names = task.attachmentNames
            if !names.contains(attachFileName) {
                names.append(attachFileName)
                task.attachmentNames = names
            }
        }
        if task.preferredContext == nil { task.preferredContext = "estudio" }
        if task.studyObjective == nil {
            task.studyObjective = SRStudyDetector.objective(title: task.title, detail: task.detail)
        }
        try? modelContext.save()
        isWorking = false
        SRHaptics.success()
        dismiss()
    }
}

/// Reads a material and lets the person point at the part that does not land.
/// Selecting a paragraph is the highest-priority source for an explanation.
struct MaterialReaderView: View {
    let material: StudyMaterial
    let onExplain: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @State private var selectedParagraph: String?

    private var paragraphs: [String] {
        material.text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 30 }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if paragraphs.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Este material no tiene texto legible.")
                            .font(.subheadline)
                            .foregroundStyle(SRDesign.secondaryInk)
                        if let fileName = material.fileName {
                            Text(fileName)
                                .font(.caption)
                                .foregroundStyle(SRDesign.secondaryInk.opacity(0.85))
                        }
                    }
                } else {
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Button {
                            withAnimation(SRDesign.quickAnimation) {
                                selectedParagraph = selectedParagraph == paragraph ? nil : paragraph
                            }
                            SRHaptics.light()
                        } label: {
                            Text(paragraph)
                                .font(.body)
                                .foregroundStyle(SRDesign.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selectedParagraph == paragraph
                                        ? SRDesign.primarySoft.opacity(0.6)
                                        : Color.clear
                                )
                                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 120)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    let fragment = selectedParagraph ?? ""
                    dismiss()
                    onExplain(fragment)
                } label: {
                    Label(
                        selectedParagraph == nil ? "Explícame esto" : "Explícame el párrafo",
                        systemImage: "text.bubble"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SRPrimaryButtonStyle())

                if selectedParagraph != nil {
                    Text("Se usará solo ese párrafo como fuente principal.")
                        .font(.caption2)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
            }
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 16)
            .padding(.top, 12)
            .background(SRDesign.background.opacity(0.96))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(material.kind.label, systemImage: material.kind.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.primary)
                Spacer()
                if let link = material.sourceURLString, let url = URL(string: link) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "safari")
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityLabel("Abrir la página original")
                }
            }
            Text(material.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Toca un párrafo para preguntar solo por él.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .padding(.top, 20)
    }
}
