import AppIntents
import SwiftUI
import WidgetKit

nonisolated struct SREntry: TimelineEntry {
    let date: Date
    let snapshot: SRWidgetSnapshot
    /// Read at timeline time so the widget follows the same appearance profile as
    /// the app, within what WidgetKit allows.
    let style: SRWidgetStyle
}

nonisolated struct SRProvider: TimelineProvider {
    func placeholder(in context: Context) -> SREntry {
        SREntry(date: .now, snapshot: .placeholder, style: .contextual)
    }

    func getSnapshot(in context: Context, completion: @escaping (SREntry) -> Void) {
        completion(
            SREntry(
                date: .now,
                snapshot: SRWidgetStore.read() ?? .placeholder,
                style: SRAppearanceReader.profile().widgetStyle
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SREntry>) -> Void) {
        let stored = SRWidgetStore.read() ?? .placeholder
        let now = Date()

        // A few entries so the wording changes on its own when the moment arrives
        // or the deadline passes, without waking the app up.
        var dates: [Date] = [now]
        if let availableFrom = stored.availableFrom, availableFrom > now {
            dates.append(availableFrom)
        }
        if let dueDate = stored.dueDate, dueDate > now {
            dates.append(dueDate)
        }
        dates.append(now.addingTimeInterval(30 * 60))
        let style = SRAppearanceReader.profile().widgetStyle
        let entries = Array(Set(dates)).sorted().map { SREntry(date: $0, snapshot: stored, style: style) }

        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

// MARK: - Views

struct SRWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SREntry

    private var tone: SRWidgetSnapshot.Tone { entry.snapshot.tone(at: entry.date) }
    private var isActionable: Bool { tone == .current || tone == .overdue || tone == .saturated }
    /// While a session runs, the widget shows that session and nothing else.
    private var isRunning: Bool { tone == .running }
    private var style: SRWidgetStyle { entry.style }

    /// "Minimal" means the task and nothing else; the state still has to be legible
    /// through composition, so the header only disappears when it is redundant.
    private var showsStatusHeader: Bool {
        switch style {
        case .minimal: return tone == .overdue
        case .contextual, .status: return true
        }
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessoryRectangular
        case .accessoryInline:
            Text(entry.snapshot.title)
        case .accessoryCircular:
            accessoryCircular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsStatusHeader {
                header
            }
            Spacer(minLength: 8)
            Text(entry.snapshot.title)
                .font(titleFont)
                .foregroundStyle(SRPalette.ink)
                .lineLimit(style == .minimal ? 4 : 3)
                .minimumScaleFactor(0.82)
                .multilineTextAlignment(.leading)
            if let secondary = smallSecondaryLine {
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(SRPalette.secondaryInk)
                    .lineLimit(2)
                    .padding(.top, 3)
            }
            Spacer(minLength: 8)
            if isRunning {
                finishButton(isCompact: true)
            } else if isActionable {
                startButton(isCompact: true)
            } else {
                quietFooter
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { background }
    }

    /// One quiet line under the title, chosen by the widget style.
    private var smallSecondaryLine: String? {
        if let session = entry.snapshot.sessionLabel(at: entry.date) { return session }
        switch style {
        case .minimal:
            return nil
        case .contextual:
            if let context = entry.snapshot.contextLabel { return context }
            return entry.snapshot.estimatedMinutes > 0 ? "\(entry.snapshot.estimatedMinutes) min" : nil
        case .status:
            return entry.snapshot.estimatedMinutes > 0
                ? "\(entry.snapshot.estimatedMinutes) min · \(entry.snapshot.openCount) abiertos"
                : "\(entry.snapshot.openCount) abiertos"
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                if showsStatusHeader {
                    header
                }
                Spacer(minLength: 10)
                Text(entry.snapshot.title)
                    .font(titleFont)
                    .foregroundStyle(SRPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let step = entry.snapshot.nextStep, !step.isEmpty, isActionable, style != .minimal {
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(SRPalette.secondaryInk)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
                Spacer(minLength: 10)
                HStack(spacing: 10) {
                    if let session = entry.snapshot.sessionLabel(at: entry.date) {
                        chip(text: session, symbol: entry.snapshot.statusSymbol(at: entry.date))
                    } else {
                    switch style {
                    case .minimal:
                        EmptyView()
                    case .contextual:
                        if let context = entry.snapshot.contextLabel {
                            chip(text: context, symbol: "calendar.badge.clock")
                        } else if entry.snapshot.estimatedMinutes > 0 {
                            chip(text: "\(entry.snapshot.estimatedMinutes) min", symbol: "clock")
                        }
                    case .status:
                        if entry.snapshot.estimatedMinutes > 0 {
                            chip(text: "\(entry.snapshot.estimatedMinutes) min", symbol: "clock")
                        }
                        if entry.snapshot.waitingCount > 0 {
                            chip(text: "\(entry.snapshot.waitingCount) esperando", symbol: "hourglass")
                        }
                    }
                    }
                }
            }

            VStack(spacing: 10) {
                Spacer(minLength: 0)
                if isRunning {
                    finishButton(isCompact: false)
                } else if isActionable {
                    startButton(isCompact: false)
                } else {
                    Button(intent: SROpenCaptureIntent()) {
                        Label("Capturar", systemImage: "square.and.pencil")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(SRPalette.primary)
                }
            }
            .frame(width: 116)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { background }
    }

    // MARK: Accessory

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.snapshot.statusLabel(at: entry.date), systemImage: entry.snapshot.statusSymbol(at: entry.date))
                .font(.caption2)
            Text(entry.snapshot.title)
                .font(.headline)
                .lineLimit(2)
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var accessoryCircular: some View {
        VStack(spacing: 1) {
            Image(systemName: entry.snapshot.statusSymbol(at: entry.date))
                .font(.system(size: 15, weight: .semibold))
            if entry.snapshot.estimatedMinutes > 0 {
                Text("\(entry.snapshot.estimatedMinutes)")
                    .font(.caption2.weight(.semibold))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: entry.snapshot.statusSymbol(at: entry.date))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
            Text(entry.snapshot.statusLabel(at: entry.date).uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
    }

    private var quietFooter: some View {
        HStack(spacing: 5) {
            Text("SinRutina")
                .font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 0)
            if entry.snapshot.openCount > 0 {
                Text("\(entry.snapshot.openCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
            }
        }
        .foregroundStyle(SRPalette.secondaryInk.opacity(0.75))
    }

    private func startButton(isCompact: Bool) -> some View {
        Button(intent: SRStartCurrentTaskIntent(taskID: entry.snapshot.taskID)) {
            HStack(spacing: 5) {
                Image(systemName: tone == .overdue ? "exclamationmark.arrow.circlepath" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(tone == .saturated ? "Solo esto" : "Empezar")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(SRPalette.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 30 : 34)
            .background(accent)
            .clipShape(.rect(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// During a session the only action worth offering is closing it.
    private func finishButton(isCompact: Bool) -> some View {
        Button(intent: SRFinishFocusIntent(taskID: entry.snapshot.taskID ?? "")) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text("Terminé")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(SRPalette.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: isCompact ? 30 : 34)
            .background(accent)
            .clipShape(.rect(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func chip(text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(SRPalette.secondaryInk)
    }

    /// Composition changes with the moment, not only the colour.
    private var titleFont: Font {
        switch tone {
        case .overdue: return .system(size: family == .systemMedium ? 20 : 17, weight: .bold)
        case .current, .saturated, .running: return .system(size: family == .systemMedium ? 19 : 16, weight: .semibold)
        default: return .system(size: family == .systemMedium ? 18 : 15, weight: .medium)
        }
    }

    private var accent: Color {
        switch tone {
        case .empty: return SRPalette.mint
        case .upcoming: return SRPalette.secondaryInk
        case .current: return SRPalette.primary
        case .overdue: return SRPalette.blush
        case .saturated: return SRPalette.lavender
        case .running: return SRPalette.sky
        }
    }

    private var background: some View {
        ZStack {
            SRPalette.surface
            // A soft wash so the widget has depth without a loud gradient.
            RadialGradient(
                colors: [accent.opacity(tone == .empty || tone == .upcoming ? 0.07 : 0.16), .clear],
                center: .topLeading,
                startRadius: 4,
                endRadius: 190
            )
            if tone == .overdue {
                // Extra non-colour cue for the overdue state.
                VStack {
                    Rectangle()
                        .fill(SRPalette.blush)
                        .frame(height: 3)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Widget

struct SinRutinaWidget: Widget {
    let kind: String = SRShared.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SRProvider()) { entry in
            SRWidgetView(entry: entry)
        }
        .configurationDisplayName("SinRutina")
        .description("La única cosa que toca ahora, con un botón para empezar.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline,
        ])
        .containerBackgroundRemovable(false)
    }
}
