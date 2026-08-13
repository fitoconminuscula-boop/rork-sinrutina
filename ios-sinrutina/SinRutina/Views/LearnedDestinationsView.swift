import SwiftUI

/// Every place SinRutina has learned, with what it actually knows about each one
/// and a way to forget it.
///
/// A place with no measured trips says so instead of showing a number.
struct LearnedDestinationsView: View {
    @Environment(\.srMetrics) private var metrics

    @State private var store = LearnedRouteStore.shared
    @State private var engine = PersonalTravelEngine.shared
    @State private var renaming: LearnedDestination?
    @State private var pendingRemoval: LearnedDestination?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Destinos aprendidos")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("Cada lugar guarda una coordenada aproximada, un radio de llegada y la duración de tus viajes. Nada más, y nada de esto sale del iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)

                if store.knownDestinations.isEmpty {
                    emptyCard
                } else {
                    ForEach(store.knownDestinations) { destination in
                        destinationCard(destination)
                    }
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, SRDesign.pagePadding)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("Destinos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $renaming) { destination in
            RenameDestinationSheet(destination: destination)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "¿Olvidar este lugar?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Olvidar y borrar sus viajes", role: .destructive) {
                if let pendingRemoval {
                    store.remove(pendingRemoval)
                    SRHaptics.light()
                }
                pendingRemoval = nil
            }
            Button("Cancelar", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Se borran el lugar y todas las duraciones aprendidas para él.")
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ningún lugar aprendido todavía")
                .font(.headline)
                .foregroundStyle(SRDesign.ink)
            Text("Un lugar aparece aquí cuando haces un viaje real hacia él y SinRutina puede medir cuánto tardaste. No se inventa ninguno.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func destinationCard(_ destination: LearnedDestination) -> some View {
        let routes = store.routes(for: destination.id)
        let samples = routes.reduce(0) { $0 + $1.sampleCount }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(destination.displayName)
                        .font(.headline)
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(subtitle(destination, samples: samples))
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Menu {
                    Button("Cambiar el nombre") { renaming = destination }
                    if !routes.isEmpty {
                        Button("Olvidar solo los viajes", role: .destructive) {
                            store.forgetRoutes(for: destination)
                            SRHaptics.light()
                        }
                    }
                    Button("Olvidar este lugar", role: .destructive) {
                        pendingRemoval = destination
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SRDesign.secondaryInk)
                        .frame(width: 32, height: 32)
                        .background(SRDesign.secondaryInk.opacity(0.09))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Opciones de \(destination.displayName)")
            }
            .padding(.bottom, routes.isEmpty ? 0 : 12)

            if routes.isEmpty {
                Text("Sin viajes medidos todavía. No hay ninguna duración aprendida para este lugar.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            } else {
                VStack(spacing: 0) {
                    ForEach(routes) { route in
                        LearnedRouteRow(route: route)
                        if route.id != routes.last?.id {
                            Divider().overlay(SRDesign.divider)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func subtitle(_ destination: LearnedDestination, samples: Int) -> String {
        var parts: [String] = []
        parts.append(samples == 0 ? "Sin viajes" : (samples == 1 ? "1 viaje" : "\(samples) viajes"))
        if let last = destination.lastVisitAt {
            parts.append("última vez \(Self.dateFormatter.string(from: last))")
        }
        parts.append("radio \(Int(destination.radiusMeters)) m")
        return parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}

/// Naming a place is the person's decision. SinRutina never infers what a location
/// means, so the field starts with whatever the calendar gave it, or empty.
struct RenameDestinationSheet: View {
    let destination: LearnedDestination

    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @State private var name: String = ""
    @State private var store = LearnedRouteStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nombre del lugar")
                .font(.title3.weight(.bold))
                .foregroundStyle(SRDesign.ink)

            TextField("Casa, consulta, universidad…", text: $name)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(SRDesign.ink)
                .padding(14)
                .background(SRDesign.elevatedSurface)
                .clipShape(.rect(cornerRadius: metrics.rowRadius))

            Text("Solo se usa en la interfaz de este iPhone. Puedes dejarlo vacío.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button("Guardar") {
                store.rename(destination, to: name)
                SRHaptics.light()
                dismiss()
            }
            .buttonStyle(SRPrimaryButtonStyle())

            Spacer(minLength: 0)
        }
        .padding(.top, 22)
        .padding(.horizontal, SRDesign.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
        .onAppear { name = destination.name ?? "" }
    }
}
