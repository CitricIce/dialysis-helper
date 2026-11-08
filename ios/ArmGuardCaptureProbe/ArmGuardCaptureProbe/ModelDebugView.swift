import Combine
import SwiftUI

/// Intentionally owns no speech, conversation, routine, or Bluetooth client.
final class ModelDebugController: ObservableObject {
    let capture = CaptureController()
    private let vision = CoachVisionPipeline(includeDebugPreview: true)
    @Published private(set) var observation = CoachVisionSnapshot()
    @Published private(set) var resultFPS = 0.0
    @Published var confidence = DetectionConfidence.preview {
        didSet { DetectionConfidence.preview = confidence; vision.setConfidenceThreshold(Float(confidence)) }
    }
    private var subscription: AnyCancellable?
    private var clock: Timer?
    private var intervalStart = 0.0
    private var results = 0

    init() {
        capture.frameObserver = { [weak vision = self.vision] frame in vision?.submit(frame) }
        vision.onResult = { [weak self] output in
            guard let self else { return }
            self.observation = output
            self.results += 1
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.intervalStart >= 1 {
                self.resultFPS = Double(self.results) / (now - self.intervalStart)
                self.intervalStart = now; self.results = 0
            }
        }
        subscription = capture.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    var frameAge: Double? {
        guard observation.receipt > 0 else { return nil }
        return max(0, ProcessInfo.processInfo.systemUptime - observation.receipt)
    }
    var recentResult: Bool { capture.isRunning && (frameAge.map { $0 <= 1 } ?? false) }
    var protectionFresh: Bool { capture.isRunning && (frameAge.map { $0 <= 0.25 } ?? false) }
    var proximityText: String {
        guard protectionFresh else { return "Distance unavailable: observation is paused or older than 250 ms." }
        if let mm = observation.distanceMM,
           FrameFreshness.isFresh(lastReceipt: observation.distanceReceipt, now: ProcessInfo.processInfo.systemUptime, timeout: 0.25) {
            return String(format: "Experimental gap: %.0f mm · %@. This test sends no band or voice commands.", mm, observation.scaleRisk.title)
        }
        switch observation.decision {
        case .unavailable(let reason): return reason
        case .clear: return "No near pair in the current depth samples."
        case .warning(_, let meters): return String(format: "Estimated fingertip gap: %.0f mm", meters * 1000)
        case .projectedOverlap: return "Overlap in the image. This does not confirm contact."
        }
    }
    func start() {
        guard !capture.isRunning, !capture.isStarting else { return }
        observation = CoachVisionSnapshot(); resultFPS = 0
        intervalStart = ProcessInfo.processInfo.systemUptime; results = 0
        vision.setConfidenceThreshold(Float(confidence)); vision.setActive(true)
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.objectWillChange.send() }
        capture.start()
    }
    func stop() {
        vision.setActive(false); capture.stop(reason: "Camera test stopped")
        clock?.invalidate(); clock = nil; resultFPS = 0
    }
}

struct ModelDebugView: View {
    @StateObject private var debug = ModelDebugController()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showHands = true
    @State private var showTips = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Camera + detection model").font(.title2.bold())
                    Text("Camera-only test. Voice, routine checks and wristband output are off.")
                        .font(.callout).foregroundStyle(.secondary)
                    preview
                    Text(debug.capture.status).font(.callout)
                    if debug.capture.needsSettings {
                        Button("Open app settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    HStack {
                        Button(debug.capture.isRunning ? "Stop camera" : "Start camera") {
                            if debug.capture.isRunning { debug.stop() } else { debug.start() }
                        }.buttonStyle(.borderedProminent).disabled(debug.capture.isStarting)
                        Spacer()
                        Label(debug.observation.modelInstalled ? (debug.observation.detectorStatus == .placeholder ? "Low-accuracy model loaded" : "Model loaded") : "Waiting for model",
                              systemImage: debug.observation.modelInstalled ? "checkmark.circle" : "hourglass")
                            .font(.caption)
                    }
                    Text(debug.observation.modelStatus).font(.caption).textSelection(.enabled)
                    GroupBox("Detection settings") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Minimum confidence"); Spacer(); Text(String(format: "%.0f%%", debug.confidence * 100)) }
                            Slider(value: $debug.confidence, in: 0.1...0.9, step: 0.05)
                                .accessibilityLabel("Detection confidence threshold")
                            Text("Lower it to inspect weaker detections. This setting also applies to the routine's experimental camera preview.")
                                .font(.caption).foregroundStyle(.secondary)
                            Toggle("Show hand boxes", isOn: $showHands)
                            Toggle("Show fingertip dots", isOn: $showTips)
                        }
                    }
                    GroupBox("Current detections") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Orange: protected tip · Green: hand · Cyan: Apple fingertips")
                                .font(.caption).foregroundStyle(.secondary)
                            if debug.observation.detections.isEmpty {
                                Text(debug.observation.modelInstalled ? "No objects above the confidence threshold. Try a clear, well-lit connector and a hand." : "Waiting for the first model result.")
                                    .font(.callout)
                            }
                            ForEach(Array(debug.observation.detections.enumerated()), id: \.offset) { _, detection in
                                HStack {
                                    Text(detection.label)
                                    Spacer()
                                    Text(String(format: "%.0f%%", detection.confidence * 100)).monospacedDigit()
                                }.font(.callout)
                            }
                            Text("\(debug.observation.fingertips.count) fingertips · \(debug.observation.handCoverageComplete ? "both hands fully tracked" : "incomplete two-hand coverage")")
                                .font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GroupBox("Depth and timing") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(debug.proximityText).font(.callout)
                            metric("Camera delivery", String(format: "%.1f frames/s", debug.capture.cameraFPS))
                            metric("Completed model results", String(format: "%.1f /s", debug.resultFPS))
                            metric("Inference pipeline", String(format: "%.1f ms", debug.observation.processingMilliseconds))
                            metric("Analysed frame age", debug.frameAge.map { String(format: "%.0f ms", $0 * 1000) } ?? "Waiting")
                            metric("Depth source", debug.capture.snapshot.depthResolution)
                            Text("Boxes are drawn on the exact frame analysed. Depth gaps still need usable LiDAR samples; inference time is not physical warning latency.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.padding()
            }
            .navigationTitle("Model test").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { debug.stop(); dismiss() } }
        }
        .onAppear { debug.start() }
        .onDisappear { debug.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { debug.stop() } }
    }

    private var preview: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = debug.observation.debugImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay { overlays }
            } else if let image = debug.capture.snapshot.colorImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay { Text("Loading first model result…").padding(8).background(.black.opacity(0.7)).foregroundStyle(.white) }
            } else {
                Rectangle().fill(.black).aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay { ProgressView("Starting camera…").tint(.white).foregroundStyle(.white) }
            }
            Text(debug.recentResult ? "Analysed frame" : "Paused / waiting / stale")
                .font(.caption.bold()).padding(6).foregroundStyle(.white)
                .background(.black.opacity(0.75)).padding(8)
        }.clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private var overlays: some View {
        GeometryReader { geometry in
            ForEach(Array(debug.observation.detections.enumerated()), id: \.offset) { _, detection in
                if showHands || detection.role != .hand {
                    let box = detection.region
                    let width = box.height * geometry.size.width
                    let height = box.width * geometry.size.height
                    let x = (1 - box.y - box.height / 2) * geometry.size.width
                    let y = (box.x + box.width / 2) * geometry.size.height
                    Rectangle().stroke(color(detection.role), lineWidth: 2)
                        .frame(width: width, height: height).position(x: x, y: y)
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2.bold()).padding(3).foregroundStyle(.black)
                        .background(color(detection.role))
                        .position(x: max(55, min(geometry.size.width - 55, x)), y: max(10, y - height / 2 + 8))
                }
            }
            if showTips {
                ForEach(Array(debug.observation.fingertips.enumerated()), id: \.offset) { _, point in
                    Circle().fill(.cyan).frame(width: 7, height: 7)
                        .position(x: (1 - point.y) * geometry.size.width, y: point.x * geometry.size.height)
                }
            }
        }.opacity(debug.recentResult ? 1 : 0.35).allowsHitTesting(false).accessibilityHidden(true)
    }
    private func color(_ role: DetectionRole) -> Color {
        switch role { case .protectedOpening: return .orange; case .hand: return .green; case .fingertip: return .cyan; case .ignored: return .gray }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }.font(.caption)
    }
}
