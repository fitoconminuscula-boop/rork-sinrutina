import SwiftUI

/// The share sheet SinRutina shows when something arrives from WhatsApp, Mail,
/// Safari or anywhere else. It reads the text on device, proposes one concrete
/// action, and lets the person place it in a single tap.
struct ShareView: View {
    let extensionContext: NSExtensionContext?

    @State private var payload = SRSharedPayload()
    @State private var suggestion: SRCaptureSuggestion?
    @State private var isReading = true
    @State private var savedState: TaskState?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            SRPalette.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                if let savedState {
                    confirmation(for: savedState)
                } else if isReading {
                    reading
                } else if let suggestion {
                    proposal(suggestion)
                } else {
                    empty
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .task { await read() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SRPalette.primary)
            Text("SinRutina")
                .font(.headline.weight(.semibold))
                .foregroundStyle(SRPalette.primary)
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SRPalette.secondaryInk)
                    .frame(width: 34, height: 34)
                    .background(SRPalette.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Cerrar")
        }
        .padding(.bottom, 22)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProgressView()
                .tint(SRPalette.primary)
            Text("Leyendo lo que compartiste…")
                .font(.body)
                .foregroundStyle(SRPalette.secondaryInk)
            Text("Se procesa en este iPhone.")
                .font(.caption)
                .foregroundStyle(SRPalette.secondaryInk.opacity(0.8))
            Spacer()
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No encontramos texto que leer")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRPalette.ink)
            Text("Prueba a compartir el mensaje como texto, un enlace o un documento.")
                .font(.body)
                .foregroundStyle(SRPalette.secondaryInk)
            Spacer()
            Button("Cerrar") { close() }
                .buttonStyle(SRSharePrimaryStyle())
        }
    }

    private func proposal(_ suggestion: SRCaptureSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Propuesta".uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(SRPalette.secondaryInk)
                        .padding(.bottom, 12)

                    Text(suggestion.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SRPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let step = suggestion.nextStep, !step.isEmpty {
                        Text(step)
                            .font(.body)
                            .foregroundStyle(SRPalette.secondaryInk)
                            .padding(.top, 7)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        chip("\(suggestion.estimatedMinutes) min", symbol: "clock")
                        if let context = suggestion.context, !context.isEmpty {
                            chip(context, symbol: "tag")
                        }
                        if let waitingFor = suggestion.waitingFor, !waitingFor.isEmpty {
                            chip(waitingFor, symbol: "person")
                        }
                    }
                    .padding(.top, 16)

                    if let excerpt = excerpt {
                        Text(excerpt)
                            .font(.footnote)
                            .foregroundStyle(SRPalette.secondaryInk)
                            .lineLimit(3)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SRPalette.primarySoft.opacity(0.45))
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .padding(.top, 18)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(SRPalette.blush)
                            .padding(.top, 14)
                    }
                }
            }

            VStack(spacing: 9) {
                Button("Hacer ahora") { save(as: .now) }
                    .buttonStyle(SRSharePrimaryStyle())

                HStack(spacing: 9) {
                    secondaryButton("Después", symbol: "calendar") { save(as: .after) }
                    secondaryButton("Esperando", symbol: "hourglass") { save(as: .waiting) }
                }

                Button("Guardar y decidir luego") { save(as: nil) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRPalette.primary)
                    .padding(.top, 2)
            }
            .padding(.top, 18)
        }
    }

    private func confirmation(for state: TaskState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(SRPalette.mint)
            Text(state == .now ? "Guardado en Ahora" : "Guardado en \(state.rawValue)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRPalette.ink)
            Text("Lo verás la próxima vez que abras SinRutina.")
                .font(.body)
                .foregroundStyle(SRPalette.secondaryInk)
            Spacer()
        }
        .task {
            try? await Task.sleep(for: .milliseconds(900))
            close()
        }
    }

    // MARK: - Pieces

    private func chip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(SRPalette.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(SRPalette.primarySoft.opacity(0.7))
        .clipShape(Capsule(style: .continuous))
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(SRPalette.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(SRPalette.surface)
            .clipShape(.rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SRPalette.divider.opacity(0.5), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var excerpt: String? {
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 40 else { return nil }
        return text
    }

    // MARK: - Behaviour

    private func read() async {
        let loaded = await ShareItemLoader.load(from: extensionContext)
        payload = loaded
        guard !loaded.isEmpty else {
            isReading = false
            return
        }
        let proposal = await SRIntelligenceService.shared.interpretSharedText(
            loaded.readableText,
            sourceApp: loaded.sourceApp
        )
        suggestion = proposal
        isReading = false
    }

    /// Hands the decision to the app. The extension never writes to the database,
    /// so the app's rules always have the last word.
    private func save(as state: TaskState?) {
        guard let suggestion else { return }
        let item = SRInboxItem(
            rawText: payload.readableText,
            linkURL: payload.url,
            attachmentName: payload.attachmentName,
            sourceApp: payload.sourceApp,
            suggestion: suggestion,
            chosenState: state
        )
        SRShareInbox.append(item)
        savedState = state ?? .after
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct SRSharePrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(SRPalette.primary)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
