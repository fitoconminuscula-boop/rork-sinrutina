import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// Editing one profile: its name, the apps it needs, how Safari behaves and which
/// sites stay reachable. Nothing here applies anything: it only describes what a
/// session of this kind should look like.
struct FocusProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    let profile: SRFocusProfileDefinition

    @State private var store = SRFocusProfileStore.shared
    @State private var screenTime = ScreenTimeService.shared
    @State private var draft: SRFocusProfileDefinition
    @State private var newApp = ""
    @State private var newDomain = ""
    @State private var showsAllowedPicker = false
    @State private var showsDistractingPicker = false

    init(profile: SRFocusProfileDefinition) {
        self.profile = profile
        _draft = State(initialValue: profile)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                nameSection
                appsSection
                screenTimeSection
                safariSection
                if draft.safariMode.allowsWebLimits { domainsSection }
                levelSection

                if !draft.isBuiltIn || draft.kind == .custom {
                    Button("Borrar este perfil") {
                        store.remove(draft)
                        SRHaptics.light()
                        dismiss()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle(draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Guardar") {
                    store.upsert(draft)
                    SRHaptics.success()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SRDesign.primary)
            }
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(
            isPresented: $showsAllowedPicker,
            selection: Binding(
                get: { screenTime.loadSelection(profileID: draft.id, role: .allowed) },
                set: { screenTime.saveSelection($0, profileID: draft.id, role: .allowed) }
            )
        )
        .familyActivityPicker(
            isPresented: $showsDistractingPicker,
            selection: Binding(
                get: { screenTime.loadSelection(profileID: draft.id, role: .distracting) },
                set: { screenTime.saveSelection($0, profileID: draft.id, role: .distracting) }
            )
        )
        #endif
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Nombre")
            TextField("Nombre del perfil", text: $draft.name)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(SRDesign.ink)
                .padding(14)
                .background(SRDesign.elevatedSurface)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Apps que necesitas")

            if draft.appNames.isEmpty {
                Text("Sin apps todavía.")
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.secondaryInk)
            } else {
                VStack(spacing: 0) {
                    ForEach(draft.appNames, id: \.self) { app in
                        HStack {
                            Text(app)
                                .font(.body)
                                .foregroundStyle(SRDesign.ink)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(SRDesign.quickAnimation) {
                                    draft.appNames.removeAll { $0 == app }
                                }
                                SRHaptics.light()
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.8))
                            }
                            .accessibilityLabel("Quitar \(app)")
                        }
                        .padding(.vertical, 12)

                        if app != draft.appNames.last {
                            Divider().overlay(SRDesign.divider)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .srCard()
            }

            HStack(spacing: 10) {
                TextField("Añadir app", text: $newApp)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(SRDesign.elevatedSurface)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit { addApp() }

                Button("Añadir") { addApp() }
                    .buttonStyle(SRQuietButtonStyle())
                    .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// The real Screen Time part: which apps iOS should keep open or close. It is
    /// separate from the names above on purpose — the names are what SinRutina
    /// shows you, the selection is what iOS can actually act on.
    private var screenTimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Bloqueo real")

            VStack(spacing: 0) {
                Button {
                    #if canImport(FamilyControls)
                    showsAllowedPicker = true
                    #endif
                } label: {
                    SettingsNavRow(
                        title: "Apps disponibles en Profundo",
                        detail: countLabel(role: .allowed),
                        symbol: "checkmark.shield"
                    )
                }
                .buttonStyle(.plain)

                Divider().overlay(SRDesign.divider).padding(.leading, 44)

                Button {
                    #if canImport(FamilyControls)
                    showsDistractingPicker = true
                    #endif
                } label: {
                    SettingsNavRow(
                        title: "Apps que cerrar en Enfoque",
                        detail: countLabel(role: .distracting),
                        symbol: "hand.raised"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .srCard()
            .disabled(!screenTime.access.isGranted)
            .opacity(screenTime.access.isGranted ? 1 : 0.55)

            if !screenTime.access.isGranted {
                Text("Para elegir apps concretas hace falta el permiso de Tiempo de uso. Sin él, la sesión funciona igual pero sin cerrar nada.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var safariSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Safari")

            VStack(spacing: 8) {
                ForEach(SRSafariMode.allCases) { mode in
                    Button {
                        withAnimation(SRDesign.quickAnimation) { draft.safariMode = mode }
                        SRHaptics.light()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: draft.safariMode == mode ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(draft.safariMode == mode ? SRDesign.primary : SRDesign.secondaryInk.opacity(0.6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SRDesign.ink)
                                Text(mode.detail)
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srSurface(radius: metrics.rowRadius, accent: draft.safariMode == mode ? SRDesign.primary : nil)
                    }
                    .buttonStyle(SRPressStyle())
                }
            }
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Sitios permitidos")

            if draft.allowedDomains.isEmpty {
                Text("Sin sitios todavía.")
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.secondaryInk)
            } else {
                VStack(spacing: 0) {
                    ForEach(draft.allowedDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                                .font(.subheadline)
                                .foregroundStyle(SRDesign.ink)
                            Spacer(minLength: 0)
                            Button {
                                withAnimation(SRDesign.quickAnimation) {
                                    draft.allowedDomains.removeAll { $0 == domain }
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.8))
                            }
                            .accessibilityLabel("Quitar \(domain)")
                        }
                        .padding(.vertical, 12)

                        if domain != draft.allowedDomains.last {
                            Divider().overlay(SRDesign.divider)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .srCard()
            }

            HStack(spacing: 10) {
                TextField("scholar.google.com", text: $newDomain)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(SRDesign.elevatedSurface)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .submitLabel(.done)
                    .onSubmit { addDomain() }

                Button("Añadir") { addDomain() }
                    .buttonStyle(SRQuietButtonStyle())
                    .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("Los límites por sitio se aplican con las APIs de Apple. Si iOS no puede aplicarlos, SinRutina te lo dice en lugar de fingirlo.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Nivel sugerido")

            HStack(spacing: 8) {
                ForEach(SRFocusLevel.allCases) { level in
                    Button {
                        withAnimation(SRDesign.quickAnimation) { draft.suggestedLevel = level }
                        SRHaptics.light()
                    } label: {
                        Text(level.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(draft.suggestedLevel == level ? SRDesign.onPrimary : SRDesign.secondaryInk)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(draft.suggestedLevel == level ? SRDesign.primary : SRDesign.elevatedSurface)
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(SRPressStyle())
                }
            }
        }
    }

    // MARK: - Actions

    private func countLabel(role: ScreenTimeService.SelectionRole) -> String {
        let count = screenTime.selectionCount(profileID: draft.id, role: role)
        return count == 0 ? "Sin elegir" : "\(count) elegidas"
    }

    private func addApp() {
        let trimmed = newApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(SRDesign.quickAnimation) {
            if !draft.appNames.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                draft.appNames.append(trimmed)
            }
            newApp = ""
        }
        SRHaptics.light()
    }

    private func addDomain() {
        let trimmed = newDomain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        guard !trimmed.isEmpty else { return }
        withAnimation(SRDesign.quickAnimation) {
            if !draft.allowedDomains.contains(trimmed) {
                draft.allowedDomains.append(trimmed)
            }
            newDomain = ""
        }
        SRHaptics.light()
    }
}
