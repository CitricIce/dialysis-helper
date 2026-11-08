import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RoutineCoachView().tabItem { Label("Practice coach", systemImage: "list.bullet.clipboard") }
            CaptureProbeView().tabItem { Label("Capture test", systemImage: "camera.viewfinder") }
        }
    }
}

struct RoutineCoachView: View {
    @StateObject private var coach = CoachViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ArmGuard").font(.largeTitle.bold())
                Text("Practice coach").font(.title2)
                Label("Practice only · clinic protocol not configured", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.orange)
                if let session = coach.session {
                    if session.phase == .idle {
                        Text(session.template.protocolNote).font(.callout)
                        Picker("Practice slot", selection: $coach.selectedSlot) {
                            ForEach(session.template.slots, id: \.self) { Text($0).tag($0) }
                        }
                        Text("These are practice labels. They do not set a daily treatment schedule.").font(.caption).foregroundStyle(.secondary)
                        Button("Start practice") { coach.start() }.buttonStyle(.borderedProminent)
                    } else {
                        HStack {
                            Text(coach.selectedSlot).font(.headline)
                            Spacer()
                            Text(session.phase.rawValue).font(.caption.monospaced())
                        }
                        ProgressView(value: Double(session.checkIndex), total: Double(session.template.checks.count))
                        if session.phase == .reviewRequired || session.reviewRequired {
                            Label("Possible overlap needs review", systemImage: "exclamationmark.octagon.fill")
                                .font(.headline).foregroundStyle(.red)
                            Text("This view cannot determine physical contact. Use your PD team's instructions. Resume cannot clear this flag.")
                        } else if session.phase == .completed || session.phase == .preparationOnly {
                            Text(session.phase == .completed ? "Practice record finished" : "Preparation practice only").font(.title2.bold())
                            Text("This record does not establish that an exchange was sterile or treatment was completed.")
                        } else if let check = session.currentCheck {
                            Text("\(min(session.checkIndex + 1, session.template.checks.count)) / \(session.template.checks.count) · \(check.title)").font(.title3.bold())
                            Text(check.prompt).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Repeat") { coach.prompt() }
                                Button("Explain") { coach.explain() }
                            }.buttonStyle(.bordered)
                            if session.phase == .checking, check.responseKind != .monitoring {
                                TextField("Describe what you checked", text: $coach.response, axis: .vertical)
                                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                                    .accessibilityIdentifier("checkResponse")
                                HStack {
                                    Button("Submit response") { coach.submit() }.buttonStyle(.borderedProminent)
                                        .disabled(coach.conversation.active)
                                    Button(coach.speech.isListening ? "Stop listening" : "Listen") {
                                        if coach.speech.isListening { coach.speech.stopListening() }
                                        else { coach.speech.stop(); coach.speech.listen() }
                                    }.buttonStyle(.bordered).disabled(coach.conversation.active)
                                }
                                if let readBack = session.pendingReadBack {
                                    Text("Your read-back: \(readBack)").font(.callout)
                                    Text("Compare it with your written instructions. The app has not verified it.").font(.caption)
                                    Button("Confirm my read-back") { coach.confirm() }.buttonStyle(.borderedProminent)
                                        .disabled(coach.conversation.active)
                                }
                            }
                            if check.responseKind == .monitoring, session.phase == .checking {
                                Button("Start experimental monitoring") { coach.arm() }
                                    .buttonStyle(.borderedProminent).disabled(!coach.canArm)
                                Button("Finish preparation practice only") { coach.finishPreparation() }.buttonStyle(.bordered)
                            }
                            if session.phase == .monitoring {
                                Button("Finish this monitoring practice") { coach.finishMonitoring() }.buttonStyle(.bordered)
                            }
                        }
                        HStack {
                            if session.phase == .paused {
                                Button("Resume check") { coach.resume() }.buttonStyle(.borderedProminent)
                            } else if session.phase == .checking || session.phase == .monitoring {
                                Button("Pause", role: .destructive) { coach.pause() }.buttonStyle(.bordered)
                            }
                            Button("New practice", role: .destructive) { showReset = true }.buttonStyle(.bordered)
                        }
                    }
                }
                Text(coach.message).font(.callout)
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                if !coach.speech.transcript.isEmpty { Text("Heard: \(coach.speech.transcript)").font(.caption) }
                visionPanel
                voicePanel
                bandPanel
                DisclosureGroup("Diagnostics and practice events") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(coach.diagnostics).font(.caption.monospaced()).textSelection(.enabled)
                        ShareLink(item: coach.diagnostics) { Label("Share diagnostics", systemImage: "square.and.arrow.up") }
                        if let url = coach.logURL {
                            ShareLink(item: url) { Label("Share event log", systemImage: "doc.text") }
                        }
                        Text("Events contain timestamps and evidence categories; no read-back text, audio or images. Voice Q&A may be retained by your Cartesia account.").font(.caption)
                    }.padding(.top, 8)
                }
            }.padding()
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { coach.backgrounded() } }
        .onDisappear { coach.backgrounded() }
        .confirmationDialog("Start a new practice record?", isPresented: $showReset, titleVisibility: .visible) {
            Button("New practice", role: .destructive) { coach.reset() }
        } message: { Text("Existing events stay on this phone. A reset does not resolve a real contamination concern.") }
    }

    private var visionPanel: some View {
        GroupBox("Camera observations") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Start camera") { coach.startCamera() }
                        .disabled(coach.capture.isRunning || coach.capture.isStarting)
                    Button("Stop camera") { coach.backgrounded() }.disabled(!coach.capture.isRunning)
                }.buttonStyle(.bordered)
                if let image = coach.capture.snapshot.colorImage {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                        .overlay {
                            GeometryReader { geometry in
                                // Native sensor -> portrait display: x=1-y, y=x.
                                // Preview and inference run at different cadences; overlay is diagnostic only.
                                if coach.fresh {
                                    ForEach(Array(coach.observation.fingertips.enumerated()), id: \.offset) { _, tip in
                                        Circle().fill(.cyan).frame(width: 7, height: 7)
                                            .position(x: (1 - tip.y) * geometry.size.width, y: tip.x * geometry.size.height)
                                    }
                                    ForEach(Array(coach.observation.regions.enumerated()), id: \.offset) { _, region in
                                        Rectangle().stroke(.orange, lineWidth: 2)
                                            .frame(width: region.height * geometry.size.width, height: region.width * geometry.size.height)
                                            .position(x: (1 - region.y - region.height / 2) * geometry.size.width,
                                                      y: (region.x + region.width / 2) * geometry.size.height)
                                    }
                                }
                            }
                        }
                }
                Text(coach.capture.status).font(.caption)
                Text(coach.riskText).font(.callout)
                if !coach.observation.modelInstalled {
                    Text("Protected-part model not installed. You can test hands, depth, label text and preparation checks. Proximity monitoring cannot start.").font(.caption).foregroundStyle(.orange)
                }
                Button("Read visible label text") { coach.scanLabel() }
                    .disabled(!coach.capture.isRunning || coach.session?.phase != .checking)
                if !coach.scannedLabel.isEmpty {
                    Text(coach.scannedLabel).font(.callout).textSelection(.enabled)
                    Text("OCR suggestion only. No prescription match or automatic check completion.").font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var voicePanel: some View {
        GroupBox("Voice and questions") {
            VStack(alignment: .leading, spacing: 10) {
                Text(coach.speech.status).font(.caption)
                Toggle("Listen after a check prompt", isOn: binding(to: coach.speech, \.handsFree))
                Text("Check responses use on-device recognition when available. Say pause, help, repeat, confirm or ask a question. Configure voice before hand preparation.").font(.caption)
                DisclosureGroup("Cartesia connection") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("https://gateway or http://Mac-name.local:8765", text: binding(to: coach.speech, \.gatewayURL))
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Gateway access token", text: binding(to: coach.speech, \.gatewayToken))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Use Cartesia for routine prompts", isOn: binding(to: coach.speech, \.useCartesia))
                        Text("The gateway token stays in app memory. Your Cartesia API key belongs on the server.").font(.caption)
                    }.padding(.top, 6)
                }
                Toggle("Allow cloud voice questions", isOn: $coach.allowCloudQuestions)
                    .onChange(of: coach.allowCloudQuestions) { _, allowed in if !allowed { coach.conversation.stop() } }
                Text("While Q&A is live, microphone audio goes to Cartesia and replies play aloud. No camera feed is uploaded. Use practice data. Questions cannot complete checks. Urgent warnings use the phone's local voice.").font(.caption)
                if coach.conversation.active {
                    Button("End voice Q&A") { coach.conversation.stop() }.buttonStyle(.borderedProminent)
                } else {
                    Button("Ask a question") { coach.askQuestion() }.buttonStyle(.bordered)
                        .disabled(!coach.allowCloudQuestions || (coach.session?.phase != .checking && coach.session?.phase != .paused))
                }
                Text(coach.conversation.status).font(.caption)
                if !coach.conversation.transcript.isEmpty { Text(coach.conversation.transcript).font(.callout) }
                Button("Mute voice now") { coach.speech.stop(); coach.conversation.stop() }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var bandPanel: some View {
        GroupBox("Wristband") {
            VStack(alignment: .leading, spacing: 10) {
                Text(coach.band.status)
                Picker("Firmware", selection: binding(to: coach.band, \.protocolMode)) {
                    Text("Existing fixed patterns").tag(BandProtocolMode.legacy)
                    Text("PWM intensity v2").tag(BandProtocolMode.intensityV2)
                }.disabled(coach.session?.phase == .monitoring)
                HStack {
                    Button("Connect") { coach.band.connect() }
                    Button("Disconnect") { coach.band.disconnect() }
                    Button("Test pulse") { coach.band.set(intensity: 180) }
                        .disabled(!coach.band.connected || coach.session?.phase == .monitoring)
                }.buttonStyle(.bordered)
                Text("Select the firmware actually installed. The motor supports variable intensity; PWM v2 requires the matching firmware update. A band connection does not verify hand hygiene.").font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Bind to the child object's mutable field without trying to replace the
    // coach's immutable reference to that child.
    private func binding<Object: AnyObject, Value>(to object: Object,
                                                   _ keyPath: ReferenceWritableKeyPath<Object, Value>) -> Binding<Value> {
        Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
    }
}
