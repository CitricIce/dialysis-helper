import SwiftUI

// MARK: - Shared look for risk levels

extension RiskLevel {
    var title: String {
        switch self {
        case .none: return "SAFE"
        case .medium: return "MEDIUM RISK"
        case .high: return "HIGH RISK"
        }
    }
    var advice: String {
        switch self {
        case .none: return "Good distance from the sterile tip."
        case .medium: return "Your fingers are getting close. Slow down and keep a gap."
        case .high: return "Stop. Move your fingers away from the sterile tip."
        }
    }
    var color: Color {
        switch self {
        case .none: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
    var symbol: String {
        switch self {
        case .none: return "checkmark.shield.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "hand.raised.fill"
        }
    }
}

enum GuardThresholds {
    static let high = ScaleRiskTracker().highThresholdMM
    static let medium = ScaleRiskTracker().mediumThresholdMM
}

// MARK: - Overlay drawn on the analysed camera frame

/// Maps native sensor coordinates (landscape) onto the portrait image the user sees.
private struct SensorMapper {
    let size: CGSize
    func point(_ p: SensorPoint) -> CGPoint { CGPoint(x: (1 - p.y) * size.width, y: p.x * size.height) }
    func rect(_ r: ProtectedRegion) -> CGRect {
        CGRect(x: (1 - r.y - r.height) * size.width, y: r.x * size.height,
               width: r.height * size.width, height: r.width * size.height)
    }
}

/// Sterile tip with its centre, safe zones drawn at the real 30/80 mm distances, fingertips,
/// and the measured gap. Distance is to the tip's nearest EDGE, not its centre: contamination
/// happens when a finger reaches any part of the tip, and centre distance would overstate the
/// gap by half the tip's size.
struct GuardOverlay: View {
    @ObservedObject var coach: CoachViewModel
    var showZones = true

    var body: some View {
        GeometryReader { geometry in
            let map = SensorMapper(size: geometry.size)
            let obs = coach.observation
            let level = coach.distanceRisk
            ZStack {
                if showZones, let mmPerPixel = obs.mmPerPixel, mmPerPixel > 0,
                   obs.imagePixelWidth > 0, obs.imagePixelHeight > 0 {
                    ForEach(Array(obs.regions.enumerated()), id: \.offset) { _, region in
                        let rect = map.rect(region)
                        zone(rect, mm: GuardThresholds.medium, color: .orange, mmPerPixel: mmPerPixel, size: geometry.size)
                        zone(rect, mm: GuardThresholds.high, color: .red, mmPerPixel: mmPerPixel, size: geometry.size)
                    }
                }
                ForEach(Array(obs.hands.enumerated()), id: \.offset) { _, hand in
                    let rect = map.rect(hand)
                    RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                }
                ForEach(Array(obs.regions.enumerated()), id: \.offset) { index, region in
                    let rect = map.rect(region)
                    let tip = obs.regionTips.indices.contains(index) ? obs.regionTips[index] : nil
                    RoundedRectangle(cornerRadius: 4).stroke(tip?.tint ?? .white, lineWidth: 2.5)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    Image(systemName: "plus").font(.caption.bold()).foregroundStyle(.white)
                        .shadow(color: .black, radius: 1).position(x: rect.midX, y: rect.midY)
                    Text(tip.map { String(format: "%@ · %.0f mm", $0.name, $0.sizeMM) } ?? "Sterile tip")
                        .font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.55), in: Capsule())
                        .position(x: min(max(rect.midX, 40), geometry.size.width - 40), y: max(rect.minY - 12, 10))
                }
                ForEach(Array(obs.fingertips.enumerated()), id: \.offset) { _, tip in
                    Circle().fill(.cyan).frame(width: 7, height: 7).position(map.point(tip))
                }
                if let hand = obs.closestHand, let edge = obs.closestSurface,
                   let mm = obs.distanceMM, coach.fresh {
                    let a = map.point(hand), b = map.point(edge)
                    let color = level == .none ? Color.cyan : level.color
                    Path { $0.move(to: a); $0.addLine(to: b) }
                        .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: level == .none ? [6, 5] : []))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                    Circle().stroke(color, lineWidth: 3).frame(width: 18, height: 18).position(a)
                    Circle().fill(color).frame(width: 8, height: 8).position(b)
                    Text(String(format: "%.0f mm", mm)).font(.headline.monospacedDigit()).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.9), in: Capsule())
                        .position(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 18)
                }
            }
        }
        .opacity(coach.displayFresh ? 1 : 0.35)
        .allowsHitTesting(false).accessibilityHidden(true)
    }

    /// The tip box grown by `mm` in every direction: everything inside is within `mm` of the tip's edge.
    private func zone(_ rect: CGRect, mm: Double, color: Color, mmPerPixel: Double, size: CGSize) -> some View {
        let pixels = mm / mmPerPixel
        let dx = pixels / coach.observation.imagePixelHeight * size.width
        let dy = pixels / coach.observation.imagePixelWidth * size.height
        let grown = rect.insetBy(dx: -dx, dy: -dy)
        return RoundedRectangle(cornerRadius: min(dx, dy))
            .fill(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: min(dx, dy)).stroke(color.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])))
            .frame(width: grown.width, height: grown.height).position(x: grown.midX, y: grown.midY)
    }
}

// MARK: - Distance gauge

struct DistanceGauge: View {
    let millimetres: Double?
    private let maxMM = 120.0

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Rectangle().fill(.red).frame(width: w * GuardThresholds.high / maxMM)
                    Rectangle().fill(.orange).frame(width: w * (GuardThresholds.medium - GuardThresholds.high) / maxMM)
                    Rectangle().fill(.green)
                }.clipShape(Capsule()).opacity(0.85)
                if let mm = millimetres {
                    Circle().fill(.white).frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.4), radius: 3)
                        .offset(x: max(0, min(w - 20, w * min(mm, maxMM) / maxMM - 10)))
                        .animation(.easeOut(duration: 0.15), value: mm)
                }
            }
        }
        .frame(height: 20)
        .overlay(alignment: .bottom) {
            HStack {
                Text("0"); Spacer()
                Text("\(Int(GuardThresholds.high))").frame(width: 30)
                Spacer()
                Text("\(Int(GuardThresholds.medium))").frame(width: 30)
                Spacer(); Text("120+ mm")
            }.font(.caption2).foregroundStyle(.secondary).offset(y: 18)
        }
        .padding(.bottom, 16)
        .accessibilityElement().accessibilityLabel(millimetres.map { String(format: "Distance %.0f millimetres", $0) } ?? "No distance")
    }
}

// MARK: - Live Guard screen

struct LiveGuardView: View {
    @ObservedObject var coach: CoachViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pulse = false
    @State private var showConnectors = false
    @State private var showSummary = false

    private var level: RiskLevel {
        if case .measuring(let level, _) = coach.guardState { return level }
        return .none
    }
    private var measuring: Bool { if case .measuring = coach.guardState { return true }; return false }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = coach.observation.debugImage ?? coach.capture.snapshot.colorImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay { if coach.observation.debugImage != nil { GuardOverlay(coach: coach) } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(coach.capture.status).font(.footnote).foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                }
            }
            // Risk border: steady orange for MEDIUM, pulsing red for HIGH.
            if measuring && level != .none {
                RoundedRectangle(cornerRadius: 44).stroke(level.color, lineWidth: level == .high ? 14 : 8)
                    .opacity(level == .high ? (pulse ? 1 : 0.35) : 0.9)
                    .ignoresSafeArea().allowsHitTesting(false)
            }
            VStack(spacing: 0) {
                topBar
                Spacer()
                statusCard
            }.padding(.horizontal, 16).padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .onAppear {
            coach.openLiveGuard()
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) { pulse = true }
        }
        .onDisappear { coach.closeLiveGuard() }
        .sheet(isPresented: $showConnectors) { ConnectorsSheet() }
        .sheet(isPresented: $showSummary) { SafetySummaryView(coach: coach).presentationDetents([.medium, .large]) }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }.accessibilityLabel("Close Live Guard")
            Spacer()
            chip(coach.band.connected ? "Band on" : "Band off", symbol: "applewatch.radiowaves.left.and.right",
                 tint: coach.band.connected ? .green : .secondary)
            Button { showConnectors = true } label: {
                chip(coach.observation.referenceTip.map { String(format: "%@ %.0f mm", $0.name, $0.sizeMM) } ?? "Tips 8 / 13 mm",
                     symbol: "ruler", tint: .secondary)
            }
            Button { showSummary = true } label: {
                Image(systemName: "chart.bar.doc.horizontal").font(.headline).frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }.accessibilityLabel("Session summary")
        }.foregroundStyle(.white).padding(.top, 8)
    }

    private func chip(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol).font(.caption.bold()).foregroundStyle(tint == .secondary ? .white : tint)
            .padding(.horizontal, 10).padding(.vertical, 8).background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch coach.guardState {
            case .cameraStarting:
                hint("camera.fill", "Starting camera…", "Prop your phone so it can see the sterile tip and your hands.")
            case .lookingForTip:
                hint("viewfinder", "Looking for a connector tip", "Point the camera at the blue or clear connector tip. Good, even light helps.")
            case .lookingForHand:
                hint("hand.point.up.left.fill", coach.observation.referenceTip.map { "\($0.name) found" } ?? "Connector tip found",
                     "Distance shows as soon as your hand is in view.")
            case .measuring(let level, let mm):
                HStack(alignment: .firstTextBaseline) {
                    Label(level.title, systemImage: level.symbol)
                        .font(.title2.weight(.heavy)).foregroundStyle(level.color)
                    Spacer()
                    Text(String(format: "%.0f", mm)).font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    + Text(" mm").font(.title3.bold()).foregroundColor(.secondary)
                }
                Text(level.advice).font(.headline)
                DistanceGauge(millimetres: mm)
            }
            statsRow
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func hint(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.cyan).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold())
                Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(title: "Closest", value: coach.stats.closestMM.map { String(format: "%.0f mm", $0) } ?? "—")
            StatTile(title: "Warnings", value: "\(coach.stats.alertCount)")
            StatTile(title: "Safe time", value: coach.stats.safeFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Connectors (fixed sizes, read-only)

extension ConnectorTip {
    var tint: Color { self == .blue ? .blue : Color(red: 0.85, green: 0.9, blue: 0.95) }
}

struct ConnectorsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ConnectorTip.allCases, id: \.self) { tip in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(tip == .blue ? Color.blue : Color.white.opacity(0.9))
                                if tip == .clear { Circle().stroke(Color.red, lineWidth: 4) }
                            }.frame(width: 36, height: 36).shadow(color: .black.opacity(0.15), radius: 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip == .blue ? "Blue tip" : "Clear tip, red tubing").font(.headline)
                                Text(tip == .blue ? "Measured at its tip" : "Measured at the very top").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.0f mm", tip.sizeMM)).font(.title3.bold().monospacedDigit())
                        }.padding(.vertical, 4)
                    }
                } header: { Text("Your connectors") } footer: {
                    Text("These sizes are fixed. ArmGuard tells the tips apart by colour and uses the tip's real size to turn pixels into millimetres.")
                }
                Section {
                    zoneRow(.high, "Within \(Int(GuardThresholds.high)) mm", "Red warning, continuous vibration")
                    zoneRow(.medium, "Within \(Int(GuardThresholds.medium)) mm", "Orange warning, pulsing vibration")
                    zoneRow(.none, "Farther away", "No warning")
                } header: { Text("Warning zones") } footer: {
                    Text("Measured from your nearest fingertip to the nearest edge of the tip. Experimental 2D estimate; it cannot confirm contact or sterility.")
                }
            }
            .navigationTitle("Connectors").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func zoneRow(_ level: RiskLevel, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: level.symbol).foregroundStyle(level.color).frame(width: 24)
            VStack(alignment: .leading) {
                Text(level == .none ? "Safe" : level.title.capitalized).font(.headline)
                Text("\(title) · \(detail)").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Session summary

struct SafetySummaryView: View {
    @ObservedObject var coach: CoachViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SafetySummaryCard(coach: coach)
                    ShareLink(item: coach.summaryText) {
                        Label("Share with my care team", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("Reset these numbers", role: .destructive) { coach.resetStats() }
                        .frame(maxWidth: .infinity)
                }.padding(20)
            }
            .navigationTitle("Session summary").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// Reusable summary card (Live Guard sheet and the finished-practice screen).
struct SafetySummaryCard: View {
    @ObservedObject var coach: CoachViewModel

    var body: some View {
        let stats = coach.stats
        VStack(alignment: .leading, spacing: 14) {
            Label("Your safety summary", systemImage: "chart.bar.doc.horizontal").font(.headline)
            if stats.measuredSeconds < 1 {
                Text("No distance measured yet. Open Live Guard and keep a connector tip and a hand in view.")
                    .foregroundStyle(.secondary)
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        summaryTile("Closest approach", stats.closestMM.map { String(format: "%.0f mm", $0) } ?? "—",
                                    color: stats.closestMM.map { $0 <= GuardThresholds.high ? .red : $0 <= GuardThresholds.medium ? .orange : .green } ?? .secondary)
                        summaryTile("Time outside warning zones", stats.safeFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "—", color: .green)
                    }
                    GridRow {
                        summaryTile("High-risk warnings", "\(stats.highAlerts)", color: stats.highAlerts > 0 ? .red : .secondary)
                        summaryTile("Medium-risk warnings", "\(stats.mediumAlerts)", color: stats.mediumAlerts > 0 ? .orange : .secondary)
                    }
                    GridRow {
                        summaryTile("Longest safe stretch", String(format: "%.0f s", stats.longestSafeStreak), color: .primary)
                        summaryTile("Distance measured", String(format: "%.0f s", stats.measuredSeconds), color: .primary)
                    }
                }
            }
            Text("Practice feedback from a 2D camera estimate. It does not confirm contact or sterility.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func summaryTile(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
