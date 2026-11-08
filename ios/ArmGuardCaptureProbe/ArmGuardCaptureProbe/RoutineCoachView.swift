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
    @State private var showLiveGuard = false
    @State private var showTipSize = false
    @State private var showSummary = false
    @State private var debugCheckID = ""
    @State private var showTyping = false
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let session = coach.session {
                        if session.phase == .idle { home(session) }
                        else if coach.ended || session.phase == .completed || session.phase == .preparationOnly { finished(session) }
                        else { inPractice(session) }
                    } else { Text(coach.message) }
                    if coach.debugControlsEnabled, let session = coach.session {
                        debugNavigation(session)
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("ArmGuard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .top) { riskBanner.padding(.horizontal) }
            .sheet(isPresented: $showSettings) { settings }
            .sheet(isPresented: $showTipSize) { TipSizeSheet(coach: coach) }
            .sheet(isPresented: $showSummary) { SafetySummaryView(coach: coach).presentationDetents([.medium, .large]) }
            .sheet(isPresented: $showCapture) { CaptureProbeView() }
            .fullScreenCover(isPresented: $showModelDebug) { ModelDebugView() }
            .fullScreenCover(isPresented: $showLiveGuard) { LiveGuardView(coach: coach) }
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

    // MARK: Home

    @ViewBuilder private func home(_ session: RoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 52)).foregroundStyle(.white, .teal)
            Text("Keep the sterile tip safe").font(.largeTitle.bold())
            Text("ArmGuard watches your hands during a PD exchange and warns you, on screen, out loud and on your wristband, before your fingers get too close.")
                .font(.body).foregroundStyle(.secondary)
        }

        VStack(spacing: 0) {
            setupRow("ruler.fill", "Tip size",
                     detail: coach.sterileTipSizeMM.map { String(format: "%.1f mm · distance warnings on", $0) } ?? "Measure once with a ruler",
                     done: coach.sterileTipSizeMM != nil) { showTipSize = true }
            Divider().padding(.leading, 56)
            setupRow("applewatch.radiowaves.left.and.right", "Wristband",
                     detail: coach.band.connected ? "Connected · vibrates on warnings" : "Optional · tap to connect",
                     done: coach.band.connected) { coach.band.connect() }
            Divider().padding(.leading, 56)
            setupRow("waveform", "Voice coach",
                     detail: coach.voiceConfigured ? "Conversational voice ready" : "Phone voice ready · add Cartesia for questions",
                     done: coach.voiceConfigured) { showSettings = true }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))

        Button { showLiveGuard = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "viewfinder").font(.title).frame(width: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Guard").font(.title3.bold())
                    Text("See the distance to the sterile tip, live").font(.subheadline).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline)
            }
            .padding(18).foregroundStyle(.white)
            .background(LinearGradient(colors: [.teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)

        VStack(spacing: 10) {
            Button {
                coach.voiceConfigured ? coach.start() : coach.start(usePhoneVoice: true)
            } label: {
                Label("Start guided practice", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            HStack {
                Text("Exchange").foregroundStyle(.secondary)
                Spacer()
                Picker("Exchange", selection: $coach.selectedSlot) {
                    ForEach(session.template.slots, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }.font(.subheadline)
        }

        Text(session.template.protocolNote).font(.footnote).foregroundStyle(.secondary)
    }

    private func setupRow(_ symbol: String, _ title: String, detail: String, done: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).foregroundStyle(.teal).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(done ? .green : .secondary)
            }.padding(14).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: During practice

    @ViewBuilder private func inPractice(_ session: RoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Step \(min(session.checkIndex + 1, session.template.checks.count)) of \(session.template.checks.count)")
                .font(.subheadline.bold()).foregroundStyle(.teal)
            ProgressView(value: Double(session.checkIndex), total: Double(session.template.checks.count))
                .tint(.teal).accessibilityLabel("Practice progress")
            Text(session.currentCheck?.title ?? "Finished").font(.largeTitle.bold())
        }
        voiceCard
        if session.reviewRequired {
            Label("Possible contact needs review", systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red).font(.headline)
            Text("Follow your care team's instructions. The camera cannot confirm contact.")
        }
        if !coach.scannedLabel.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Label I can see", systemImage: "text.viewfinder").font(.headline)
                Text(coach.scannedLabel).textSelection(.enabled)
                Text("Compare it with your written instructions.").font(.footnote).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        if session.currentCheck?.responseKind == .monitoring || session.phase == .monitoring {
            cameraPreview
        }
        Button { showLiveGuard = true } label: {
            Label("Open Live Guard", systemImage: "viewfinder").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).controlSize(.large)
        HStack(spacing: 12) {
            if !coach.voiceEnabled {
                Button { coach.resumeVoice() } label: { Label("Resume voice", systemImage: "mic.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            } else if session.phase == .paused {
                Button { coach.resume() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { coach.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            Button(role: .destructive) { coach.endSession() } label: { Text("End").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }.controlSize(.large)
        Button("Type instead of speaking") { showTyping = true }.font(.footnote).frame(maxWidth: .infinity)
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(coach.conversation.active ? coach.conversation.status : coach.speech.status,
                  systemImage: coach.conversation.active || coach.speech.isListening ? "waveform" : "mic")
                .font(.subheadline).foregroundStyle(.secondary)
                .symbolEffect(.variableColor.iterative, isActive: coach.conversation.active || coach.speech.isListening)
            Text(coach.conversation.active && !coach.conversation.lastReply.isEmpty
                 ? coach.conversation.lastReply : coach.message)
                .font(.title3).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("assistantReply")
            if !coach.ended {
                Text(coach.session?.responseInstruction ?? "Say pause, or ask a question.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var cameraPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = coach.observation.debugImage ?? coach.capture.snapshot.colorImage {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .overlay { if coach.observation.debugImage != nil { GuardOverlay(coach: coach) } }
                    .frame(maxHeight: 300).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .onTapGesture { showLiveGuard = true }
            } else {
                Label("Waiting for the camera", systemImage: "camera").frame(maxWidth: .infinity, minHeight: 140)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            }
            Label(coach.cameraMessage, systemImage: "camera.viewfinder").font(.footnote).foregroundStyle(.secondary)
            if !coach.capture.isRunning {
                Button("Start camera") { coach.startCamera() }.disabled(coach.capture.isStarting)
            }
            if coach.capture.needsSettings {
                Button("Open app settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            DisclosureGroup("Camera details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(coach.capture.status)
                    Text(coach.observation.modelStatus).textSelection(.enabled)
                    Text("\(coach.observation.detections.count) boxes · \(coach.observation.fingertips.count) fingertips · " +
                         (coach.observationAge.map { String(format: "analysed frame %.0f ms old", $0 * 1000) } ?? "waiting for analysis"))
                        .monospacedDigit()
                    if !coach.displayFresh { Text("Analysis waiting, stopped or stale").foregroundStyle(.orange) }
                    if coach.session?.template.detectorStatus != .experimental {
                        HStack { Text("Detection sensitivity"); Spacer(); Text(String(format: "%.0f%%", coach.detectionConfidence * 100)) }
                        Slider(value: $coach.detectionConfidence, in: 0.1...0.9, step: 0.05)
                    }
                }.font(.caption)
            }.font(.footnote)
        }
    }

    // MARK: Finished

    @ViewBuilder private func finished(_ session: RoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: session.reviewRequired ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(session.reviewRequired ? .red : .green)
            Text(session.reviewRequired ? "Practice paused for review" : "Practice complete").font(.largeTitle.bold())
            if coach.ended { Text(coach.message).foregroundStyle(.secondary) }
        }
        if !coach.ended {
            voiceCard
            Button(role: .destructive) { coach.endSession() } label: { Text("End session").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
        SafetySummaryCard(coach: coach)
        ShareLink(item: coach.summaryText) {
            Label("Share summary with my care team", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered).controlSize(.large)
        Button { showReset = true } label: {
            Label("New practice", systemImage: "arrow.counterclockwise").font(.headline).frame(maxWidth: .infinity)
        }.buttonStyle(.borderedProminent).controlSize(.large)
    }

    // MARK: Warning banner

    @ViewBuilder private var riskBanner: some View {
        if coach.session?.reviewRequired == true || coach.riskLevel != .none {
            let review = coach.session?.reviewRequired == true
            let level: RiskLevel = review ? .high : coach.riskLevel
            let mm = coach.distanceRisk != .none ? coach.observation.distanceMM : nil
            HStack(spacing: 12) {
                Image(systemName: review ? "exclamationmark.octagon.fill" : level.symbol).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review ? "CHECK FOR CONTACT" : level.title + (mm.map { String(format: " · %.0f mm", $0) } ?? ""))
                        .font(.headline.weight(.heavy))
                    Text(review ? "Pause and follow your care team's instructions." : level.advice).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(level == .high ? Color.white : Color.black)
            .background(level.color, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: level.color.opacity(0.4), radius: 8, y: 3)
            .onTapGesture { showLiveGuard = true }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Settings

    private var settings: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showSettings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showTipSize = true } } label: {
                        HStack {
                            Label("Sterile tip size", systemImage: "ruler")
                            Spacer()
                            Text(coach.sterileTipSizeMM.map { String(format: "%.1f mm", $0) } ?? "Not set").foregroundStyle(.secondary)
                        }
                    }
                    Text(coach.distanceText).font(.footnote)
                } header: { Text("Distance warnings") } footer: {
                    Text("Medium risk within \(Int(GuardThresholds.medium)) mm (pulsing band), high risk within \(Int(GuardThresholds.high)) mm (continuous band). Experimental 2D estimate; not a contact or sterility check.")
                }
                Section {
                    LabeledContent("Status", value: coach.band.status)
                    Picker("Installed firmware", selection: binding(to: coach.band, \.protocolMode)) {
                        Text("Original patterns").tag(BandProtocolMode.legacy)
                        Text("Variable intensity").tag(BandProtocolMode.intensityV2)
                    }.disabled(coach.session?.phase == .monitoring)
                    if coach.band.connected {
                        Button("Test vibration") { coach.band.set(intensity: 180) }
                            .disabled(coach.session?.phase == .monitoring)
                        Button("Disconnect", role: .destructive) { coach.band.disconnect() }
                    } else {
                        Button("Connect wristband") { coach.band.connect() }
                    }
                } header: { Text("Wristband") } footer: {
                    Text("Choose the firmware installed on the band. Variable intensity needs the updated firmware.")
                }
                Section {
                    Text("Connect once before starting. During conversation, your microphone audio goes to Cartesia. Camera images stay on your phone.")
                        .font(.footnote)
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
                } header: { Text("Voice coach") } footer: {
                    Text("Phone voice can guide the checks and listen for replies. Open-ended questions need Cartesia.")
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
            }.navigationTitle("Settings")
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
