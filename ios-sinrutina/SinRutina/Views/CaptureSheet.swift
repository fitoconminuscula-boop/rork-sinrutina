import SwiftUI
import SwiftData

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isFocused: Bool
    @State private var text = ""
    @State private var dictation = VoiceDictationService()
    @State private var textBeforeDictation = ""
    @State private var dictationAlert: String?
    @State private var preview: SRCaptureSuggestion?
    @State private var isReading = false
    @State private var previewTask: Task<Void, Never>?
    /// Files already copied into the app group, waiting for a task to belong to.
    @State private var attachments: [String] = []
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    SRLogo(size: 34)
                    Text("Escribe o dicta cualquier cosa…")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)

                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.title3)
                    .foregroundStyle(SRDesign.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 130)
                    .padding(14)
                    .background(SRDesign.primarySoft.opacity(0.52))
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("tengo que hablar con mi mamá por el médico pero después de las 6")
                                .font(.title3)
                                .foregroundStyle(SRDesign.secondaryInk.opacity(0.72))
                                .padding(.horizontal, 30)
                                .padding(.vertical, 28)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 12) {
                    Button {
                        toggleDictation()
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                            Text(dictation.isListening ? "Terminar dictado" : "Dictar")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(dictation.isListening ? SRDesign.blush : SRDesign.primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 13)
                        .srGlassCapsule(tint: dictation.isListening ? SRDesign.blush : nil)
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityHint("Convierte tu voz en texto")

                    if dictation.isListening {
                        Text("Te escucho…")
                            .font(.footnote)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .transition(.opacity)
                    }

                    SRAttachButton(label: "Adjuntar", isCompact: true) { names in
                        withAnimation(SRDesign.quickAnimation) {
                            attachments.append(contentsOf: names.filter { !attachments.contains($0) })
                        }
                    }

                    Spacer(minLength: 0)
                }
                .animation(SRDesign.standardAnimation, value: dictation.isListening)

                if !attachments.isEmpty {
                    SRAttachmentChips(names: attachments) { name in
                        attachments.removeAll { $0 == name }
                        AttachmentStore.remove(name)
                    }
                    .transition(.opacity)
                }

                previewCard

                Spacer(minLength: 0)

                Button("Guardar") {
                    save()
                }
                .buttonStyle(SRPrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, SRDesign.pagePadding)
            .background(SRDesign.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .alert("Dictado", isPresented: Binding(get: { dictationAlert != nil }, set: { if !$0 { dictationAlert = nil } })) {
            Button("Entendido") {
                dictationAlert = nil
                dictation.dismissStatusMessage()
            }
        } message: {
            Text(dictationAlert ?? "")
        }
        .onChange(of: dictation.transcript) { _, spoken in
            guard dictation.isListening, !spoken.isEmpty else { return }
            let separator = textBeforeDictation.isEmpty ? "" : " "
            text = textBeforeDictation + separator + spoken
        }
        .onChange(of: text) { _, newValue in
            schedulePreview(for: newValue)
        }
        .onDisappear {
            _ = dictation.stop()
            previewTask?.cancel()
            // Nothing was saved, so nothing should stay on disk.
            if !didSave {
                for name in attachments { AttachmentStore.remove(name) }
            }
        }
        .onAppear {
            isFocused = true
        }
    }

    /// A quiet preview of what SinRutina understood. It is a proposal, so it is
    /// shown as information, never as a form to fill in.
    @ViewBuilder
    private var previewCard: some View {
        if let preview {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: preview.usedOnDeviceModel ? "cpu" : "text.magnifyingglass")
                        .font(.system(size: 11, weight: .bold))
                    Text(preview.usedOnDeviceModel ? "Leído en este iPhone" : "Lectura local")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.5)
                    Spacer(minLength: 0)
                    if isReading {
                        ProgressView().controlSize(.mini).tint(SRDesign.primary)
                    }
                }
                .foregroundStyle(SRDesign.primary)

                Text(preview.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    tag(preview.suggestedState.rawValue, symbol: preview.suggestedState.symbolName)
                    tag("\(preview.estimatedMinutes) min", symbol: "clock")
                    if let availableFrom = preview.availableFrom {
                        tag(SRWidgetSnapshot.timeFormatter.string(from: availableFrom), symbol: "clock.badge")
                    }
                    if let waitingFor = preview.waitingFor, !waitingFor.isEmpty {
                        tag(waitingFor, symbol: "person")
                    }
                }

                if let step = preview.nextStep, !step.isEmpty {
                    Text("Primer paso: \(step.lowercased())")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }

                if preview.isTooBig, !preview.subtasks.isEmpty {
                    Text("Parece grande. Al guardarlo te propondrá empezar por: \(preview.subtasks[0].lowercased())")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SRDesign.surface)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SRDesign.divider.opacity(0.45), lineWidth: 0.7)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            .animation(SRDesign.softAnimation, value: preview)
        }
    }

    private func tag(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(SRDesign.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(SRDesign.primarySoft.opacity(0.72))
        .clipShape(Capsule(style: .continuous))
    }

    /// Debounced so the model is not asked on every keystroke.
    private func schedulePreview(for value: String) {
        previewTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else {
            preview = nil
            isReading = false
            return
        }
        isReading = true
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            let suggestion = await SRIntelligenceService.shared.suggestion(for: trimmed)
            guard !Task.isCancelled else { return }
            preview = suggestion
            isReading = false
        }
    }

    private func toggleDictation() {
        if dictation.isListening {
            _ = dictation.stop()
            dictation.reset()
            SRHaptics.light()
            isFocused = true
            return
        }

        isFocused = false
        textBeforeDictation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        SRHaptics.soft()
        Task {
            let started = await dictation.start()
            if !started {
                dictationAlert = dictation.statusMessage ?? "No pudimos escuchar ahora mismo."
            }
        }
    }

    private func save() {
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A file on its own is already something to do, so it can be saved without text.
        let fallbackText = rawText.isEmpty ? titleFromAttachments() : rawText
        guard !fallbackText.isEmpty else { return }
        previewTask?.cancel()
        didSave = true

        // Use whatever the reader already produced; only wait if there is nothing.
        if let preview, !rawText.isEmpty {
            let task = SRTaskCommands.create(from: preview, source: "captura", context: modelContext)
            attach(to: task)
            SRHaptics.success()
            dismiss()
            return
        }
        Task {
            let suggestion = await SRIntelligenceService.shared.suggestion(for: fallbackText)
            let task = SRTaskCommands.create(from: suggestion, source: "captura", context: modelContext)
            attach(to: task)
            SRHaptics.success()
            dismiss()
        }
    }

    /// When only files were attached, the first file name is the honest title.
    private func titleFromAttachments() -> String {
        guard let first = attachments.first else { return "" }
        let base = (first as NSString).deletingPathExtension
        return attachments.count == 1 ? base : "\(base) y \(attachments.count - 1) más"
    }

    private func attach(to task: TaskItem) {
        guard !attachments.isEmpty else { return }
        var names = task.attachmentNames
        for name in attachments where !names.contains(name) {
            names.append(name)
        }
        task.attachmentNames = names
        try? modelContext.save()
    }
}
