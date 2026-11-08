import SwiftUI

struct ContentView: View {
    var body: some View { RoutineCoachView() }
}

struct RoutineCoachView: View {
    @StateObject private var coach = CoachViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showCapture = false
    @State private var showModelDebug = false
    @State private var debugCheckID = ""
    @State private var showTyping = false
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Practice with ArmGuard").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Voice and wristband setup")
                    }
                    if let session = coach.session {
                        if session.phase == .idle {
                            Text("Let's get ready.").font(.largeTitle.bold())
                            Text("Set your phone in place. Once we start, you can talk to me as you go.")
                                .font(.title3).foregroundStyle(.secondary)
                            Text(session.template.protocolNote).font(.callout).foregroundStyle(.secondary)
                            Picker("Practice", selection: $coach.selectedSlot) {
                                ForEach(session.template.slots, id: \.self) { Text($0).tag($0) }
                            }.pickerStyle(.menu)
                            Button(coach.voiceConfigured ? "Start practice" : "Set up voice") {
                                if coach.voiceConfigured { coach.start() } else { showSettings = true }
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                            Text("Cartesia provides the conversational voice. Connect it before preparing your hands.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            ProgressView(value: Double(session.checkIndex), total: Double(session.template.checks.count))
                                .accessibilityLabel("Practice progress")
                            Text(coach.ended ? "Session ended" : (session.currentCheck?.title ?? "Finished"))
                                .font(.largeTitle.bold())
                            voiceCard
                            if session.reviewRequired {
                                Label("Possible contact needs review", systemImage: "exclamationmark.octagon.fill")
                                    .foregroundStyle(.red).font(.headline)
                                Text("Follow your care team's instructions. The camera cannot confirm contact.")
                            }
                            if !coach.scannedLabel.isEmpty {
                                Text("Visible label text").font(.headline)
                                Text(coach.scannedLabel).textSelection(.enabled)
                                Text("Compare it with your written instructions.").font(.footnote).foregroundStyle(.secondary)
                            }
                            if session.currentCheck?.responseKind == .monitoring || session.phase == .monitoring {
                                cameraPreview
                            }
                            if coach.ended {
                                Button("New practice") { showReset = true }.buttonStyle(.borderedProminent)
                            } else {
                                HStack(spacing: 20) {
                                    if !coach.voiceEnabled {
                                        Button("Resume voice") { coach.resumeVoice() }.buttonStyle(.borderedProminent)
                                    } else if session.phase == .paused {
                                        Button("Resume") { coach.resume() }.buttonStyle(.bordered)
                                    } else {
                                        Button("Pause") { coach.pause() }.buttonStyle(.bordered)
                                    }
                                    Button("End session") { coach.endSession() }.foregroundStyle(.secondary)
                                }
                                Button("Type instead") { showTyping = true }.font(.footnote)
                            }
                        }
                    } else { Text(coach.message) }
                    Button {
                        coach.backgrounded(); showModelDebug = true
                    } label: {
                        Label("Test camera + model", systemImage: "viewfinder")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).controlSize(.large)
                    Text("Run detection without voice or routine checks.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if coach.debugControlsEnabled, let session = coach.session {
                        debugNavigation(session)
                    }
                }.padding(24)
            }
            .navigationTitle("ArmGuard").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .top) { riskBanner.padding(.horizontal) }
            .sheet(isPresented: $showSettings) { settings }
            .sheet(isPresented: $showCapture) { CaptureProbeView() }
            .fullScreenCover(isPresented: $showModelDebug) { ModelDebugView() }
            .sheet(isPresented: $showTyping) {
                NavigationStack {
                    Form {
                        TextField("Your reply or question", text: $coach.response, axis: .vertical)
                        Button("Send") { coach.submit(); showTyping = false }
                    }.navigationTitle("Type a reply")
                        .toolbar { Button("Close") { showTyping = false } }
                }
            }
            .confirmationDialog("Start another practice?", isPresented: $showReset, titleVisibility: .visible) {
                Button("New practice") { coach.reset() }
            } message: { Text("A new practice record does not resolve a real concern about contact.") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { coach.backgrounded() }
            else if phase == .active { coach.foregrounded() }
        }
        .onDisappear { coach.backgrounded() }
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(coach.conversation.active ? coach.conversation.status : coach.speech.status,
                  systemImage: coach.conversation.active || coach.speech.isListening ? "waveform" : "mic")
                .font(.subheadline).foregroundStyle(.secondary)
            Text(coach.conversation.active && !coach.conversation.lastReply.isEmpty
                 ? coach.conversation.lastReply : coach.message)
                .font(.title3).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistantReply")
            if !coach.ended {
                Text(coach.session?.responseInstruction ?? "Say pause, or ask a question.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = coach.observation.debugImage ?? coach.capture.snapshot.colorImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay { if coach.observation.debugImage != nil { detectionOverlay } }
                    .frame(maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("Waiting for a camera frame").frame(maxWidth: .infinity, minHeight: 120)
                    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            }
            Text(coach.capture.status).font(.caption)
            Label(coach.cameraMessage, systemImage: "camera")
                .font(.footnote).foregroundStyle(.secondary)
            Text(coach.observation.modelStatus).font(.caption).textSelection(.enabled)
            Text("\(coach.observation.detections.count) boxes · \(coach.observation.fingertips.count) fingertips · " +
                 (coach.observationAge.map { String(format: "analysed frame %.0f ms old", $0 * 1000) } ?? "waiting for analysis"))
                .font(.caption.monospacedDigit())
            if !coach.displayFresh { Text("Analysis waiting, stopped or stale").font(.caption).foregroundStyle(.orange) }
            if coach.session?.template.detectorStatus != .experimental {
                HStack { Text("Preview confidence"); Spacer(); Text(String(format: "%.0f%%", coach.detectionConfidence * 100)) }
                    .font(.caption)
                Slider(value: $coach.detectionConfidence, in: 0.1...0.9, step: 0.05)
                Text("Lower this to inspect weak predictions. The low-accuracy model does not control warnings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !coach.capture.isRunning {
                Button("Start camera") { coach.startCamera() }.disabled(coach.capture.isStarting)
            }
            if coach.capture.needsSettings {
                Button("Open app settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }

    @ViewBuilder private var riskBanner: some View {
        if coach.session?.reviewRequired == true || coach.riskLevel != .none {
            let review = coach.session?.reviewRequired == true
            let high = review || coach.riskLevel == .high
            Label(review ? "Pause and check for possible contact" : (high ? "Move your fingers away" : "Your fingers are getting close"),
                  systemImage: high ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.headline).padding().frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(high ? Color.white : Color.black)
                .background(high ? Color.red : Color.orange, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var detectionOverlay: some View {
        GeometryReader { geometry in
                ForEach(Array(coach.observation.detections.enumerated()), id: \.offset) { _, detection in
                    let region = detection.region
                    let color: Color = detection.role == .protectedOpening ? .orange : (detection.role == .hand ? .green : .gray)
                    Rectangle().stroke(color, lineWidth: 2)
                        .frame(width: region.height * geometry.size.width, height: region.width * geometry.size.height)
                        .position(x: (1 - region.y - region.height / 2) * geometry.size.width,
                                  y: (region.x + region.width / 2) * geometry.size.height)
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2.bold()).foregroundStyle(color)
                        .position(x: max(55, min(geometry.size.width - 55, (1 - region.y - region.height / 2) * geometry.size.width)),
                                  y: max(10, region.x * geometry.size.height + 8))
                }
                ForEach(Array(coach.observation.fingertips.enumerated()), id: \.offset) { _, point in
                    Circle().fill(.cyan).frame(width: 6, height: 6)
                        .position(x: (1 - point.y) * geometry.size.width, y: point.x * geometry.size.height)
                }
        }.opacity(coach.displayFresh ? 1 : 0.3).allowsHitTesting(false).accessibilityHidden(true)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Voice setup") {
                    Text("Connect once before starting. During conversation, your microphone audio goes to Cartesia. Camera images stay on your phone.")
                    if coach.speech.connectionMode == .direct {
                        SecureField("Cartesia API key", text: binding(to: coach.speech, \.cartesiaAPIKey))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                        Text("Saved in this iPhone's Keychain. The phone connects directly to Cartesia over the internet; no laptop is needed after installation.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        TextField("Hosted voice server address", text: binding(to: coach.speech, \.gatewayURL))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Access code", text: binding(to: coach.speech, \.gatewayToken))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    }
                    Toggle("Allow Cartesia voice conversation", isOn: $coach.allowCloudQuestions)
                    DisclosureGroup("Advanced voice settings") {
                        Picker("Connection", selection: binding(to: coach.speech, \.connectionMode)) {
                            Text("Direct from this iPhone").tag(VoiceConnectionMode.direct)
                            Text("Hosted voice server").tag(VoiceConnectionMode.server)
                        }
                        TextField("Voice ID", text: binding(to: coach.speech, \.voiceID))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Agent ID", text: binding(to: coach.speech, \.agentID))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if coach.session?.phase != .idle, !coach.ended {
                        Button("Connect Cartesia voice") { coach.connectVoice(); showSettings = false }
                            .disabled(!coach.voiceConfigured || !coach.voiceEnabled)
                    }
                    Button("Try phone voice") {
                        if coach.session?.phase == .idle { coach.start(usePhoneVoice: true) }
                        else { coach.usePhoneVoice() }
                        showSettings = false
                    }
                    Text("Phone voice can guide the checks and listen for replies. Open-ended questions need Cartesia.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Wristband") {
                    Text(coach.band.status)
                    Picker("Installed firmware", selection: binding(to: coach.band, \.protocolMode)) {
                        Text("Original patterns").tag(BandProtocolMode.legacy)
                        Text("Variable intensity").tag(BandProtocolMode.intensityV2)
                    }.disabled(coach.session?.phase == .monitoring)
                    HStack {
                        Button("Connect") { coach.band.connect() }
                        Spacer()
                        Button("Disconnect") { coach.band.disconnect() }
                    }
                    Button("Test vibration") { coach.band.set(intensity: 180) }
                        .disabled(!coach.band.connected || coach.session?.phase == .monitoring)
                    Text("Choose the firmware installed on the band. Variable intensity needs the updated firmware.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup("Developer tools") {
                        Button("Camera + model test (no voice)") {
                            coach.backgrounded(); showSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showModelDebug = true }
                        }
                        Button("Camera and depth test") {
                            coach.backgrounded(); showSettings = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showCapture = true }
                        }
                        Toggle("Routine debug controls", isOn: $coach.debugControlsEnabled)
                        Text("Shows skip and jump controls on the main screen. Skips are logged as unverified debugging. Camera readiness and contact-review gates still apply.")
                            .font(.footnote)
                        Text(coach.diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: coach.diagnostics) { Text("Share diagnostics") }
                        if let url = coach.logURL { ShareLink(item: url) { Text("Share practice log") } }
                        Text("Practice logs contain event times and categories, without audio, images or your spoken details. Cartesia may retain call records under your account settings.")
                            .font(.footnote)
                    }
                }
            }.navigationTitle("Voice and wristband")
                .toolbar { Button("Done") { showSettings = false } }
        }
    }
    private func debugNavigation(_ session: RoutineSession) -> some View {
        GroupBox("Routine debugging") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Jump to step", selection: $debugCheckID) {
                    Text("Choose a step").tag("")
                    ForEach(session.template.checks) { check in Text(check.title).tag(check.id) }
                }
                Button("Jump to selected step") { coach.debugJump(to: debugCheckID) }
                    .disabled(debugCheckID.isEmpty || session.reviewRequired)
                Button("Skip current step") { coach.debugSkipStep() }
                    .disabled(session.phase == .idle || session.phase == .completed || session.phase == .preparationOnly || session.reviewRequired)
                Text("You can also say ‘skip this step’ during voice practice. Debug navigation does not complete a check or start monitoring.")
                    .font(.caption).foregroundStyle(.secondary)
                if session.reviewRequired {
                    Text("A contact-review flag cannot be bypassed. Use the separate camera + model test for detection debugging.")
                        .font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func binding<Object: AnyObject, Value>(to object: Object,
                                                  _ keyPath: ReferenceWritableKeyPath<Object, Value>) -> Binding<Value> {
        Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
}
