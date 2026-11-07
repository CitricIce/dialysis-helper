import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var capture = CaptureController()
    @Environment(\.scenePhase) private var scenePhase

    private var measurementIsLive: Bool {
        capture.isRunning && capture.cameraFresh && capture.depthFresh && capture.previewFresh
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ArmGuard").font(.largeTitle.bold())
                    Text("Camera + LiDAR hardware test").font(.title3)
                    Label(capture.supportsLiDAR ? "Rear LiDAR supported" : "Rear LiDAR unavailable",
                          systemImage: capture.supportsLiDAR ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(capture.supportsLiDAR ? .green : .orange)
                }

                Text(capture.status)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(measurementIsLive ? Color.green.opacity(0.12) : Color.orange.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("captureStatus")

                HStack {
                    Button(action: { capture.start() }) {
                        Label(capture.isStarting ? "Requesting access…" : "Start camera", systemImage: "camera")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(capture.isRunning || capture.isStarting)
                    .accessibilityIdentifier("startCapture")
                    Button("Stop", role: .destructive) { capture.stop() }
                        .buttonStyle(.bordered)
                        .disabled(!capture.isRunning)
                        .accessibilityIdentifier("stopCapture")
                }

                if capture.needsSettings {
                    Button("Open app settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    PreviewPanel(title: "Camera", image: capture.snapshot.colorImage,
                                 fresh: capture.isRunning && capture.cameraFresh && capture.previewFresh)
                    PreviewPanel(title: "LiDAR depth", image: capture.snapshot.depthImage,
                                 fresh: measurementIsLive)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("Center depth").font(.headline)
                    Spacer()
                    if measurementIsLive, let meters = capture.snapshot.summary?.centerMeters {
                        Text(String(format: "%.1f cm", meters * 100))
                            .font(.title2.monospacedDigit().bold())
                            .accessibilityIdentifier("centerDepth")
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                }
                Text("Distance from the camera at the crosshair (median of a small depth patch). This is not a fingertip-to-prop gap.")
                    .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Depth colors").font(.headline)
                    LinearGradient(colors: [.red, .green, .blue], startPoint: .leading, endPoint: .trailing)
                        .frame(height: 10).clipShape(Capsule())
                    HStack {
                        Text("Near: 15 cm")
                        Spacer()
                        Text("Far: 200+ cm")
                    }.font(.caption)
                    Text("Black: invalid depth. Gray: low or unknown confidence. Colors use a fixed scale; readings can still be inaccurate.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                GroupBox("Capture diagnostics") {
                    VStack(spacing: 8) {
                        diagnostic("Camera source", capture.snapshot.colorResolution)
                        diagnostic("Depth source", capture.snapshot.depthResolution)
                        diagnostic("Camera frames", "\(capture.frameCount)")
                        diagnostic("Frames containing depth", "\(capture.depthFrameCount)")
                        diagnostic("Camera delivery", String(format: "%.1f fps", capture.cameraFPS))
                        diagnostic("Depth-bearing delivery", String(format: "%.1f fps", capture.depthFPS))
                        diagnostic("Medium/high-confidence depth", measurementIsLive
                                   ? String(format: "%.0f%%", (capture.snapshot.summary?.usableFraction ?? 0) * 100) : "—")
                        diagnostic("Center samples", measurementIsLive
                                   ? "\(capture.snapshot.summary?.centerSampleCount ?? 0)" : "—")
                        diagnostic("Preview conversion", capture.previewFresh
                                   ? String(format: "%.1f ms", capture.snapshot.processingMilliseconds) : "—")
                        diagnostic("AR tracking", capture.tracking)
                    }.padding(.top, 4)
                }
                Text(capture.snapshot.note).font(.caption).foregroundStyle(.secondary)
                Text("Capture rates count app-delivered frames. Preview refresh is capped at 10 fps. Conversion time is not end-to-end camera latency.")
                    .font(.caption).foregroundStyle(.secondary)

                ShareLink(item: capture.diagnostics) {
                    Label("Share diagnostics", systemImage: "square.and.arrow.up")
                }.buttonStyle(.bordered)

                Text("Point at a book or tabletop, then move your hand through the center. Nothing is recorded.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active && capture.isRunning {
                capture.stop(reason: "Paused while the app was inactive. Press Start to resume.")
            }
        }
        .onDisappear { capture.stop() }
    }

    private func diagnostic(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }.font(.caption)
    }
}

private struct PreviewPanel: View {
    let title: String
    let image: CGImage?
    let fresh: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold())
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().interpolation(title == "Camera" ? .medium : .none)
                        .scaledToFit()
                        .opacity(fresh ? 1 : 0.3)
                    Image(systemName: "plus").foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                } else {
                    Image(systemName: "camera.metering.center.weighted")
                        .font(.title).foregroundStyle(.gray)
                }
                if !fresh {
                    Text(image == nil ? "No frames" : "Paused / stale")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(6).background(.black.opacity(0.8), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(8)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("\(title): \(fresh ? "live" : "unavailable or stale")")
        }
        .frame(maxWidth: .infinity)
    }
}
