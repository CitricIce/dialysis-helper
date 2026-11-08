import SwiftUI

struct ContentView: View {
    var body: some View { RoutineCoachView() }
}

struct RoutineCoachView: View {
    @StateObject private var coach = CoachViewModel()
    @StateObject private var planner = PracticePlanner()
    @AppStorage("sterlingDeveloperMode") private var developerMode = false
    @State private var editingRoutine: PracticeRoutine?
    @State private var activeRoutineID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showCapture = false
    @State private var showModelDebug = false
    @State private var showLiveGuard = false
    @State private var showConnectors = false
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
                    if developerMode && coach.debugControlsEnabled, let session = coach.session {
                        debugNavigation(session)
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .tint(SterlingStyle.accent)
            .navigationTitle(coach.session?.phase == .idle ? "" : coach.selectedSlot)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if coach.session?.phase != .idle { SterlingRingMark().frame(width: 34, height: 34) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                        .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .top) { riskBanner.padding(.horizontal) }
            .sheet(isPresented: $showSettings) { settings }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditor(routine: routine, isNew: !planner.routines.contains(where: { $0.id == routine.id }),
                    checks: coach.session?.template.checks ?? [], save: planner.save, delete: planner.delete)
            }
            .sheet(isPresented: $showConnectors) { ConnectorsSheet() }
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
            .confirmationDialog("Return to my routines?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Return to my routines") { returnHome() }
            } message: {
                Text("Starting a new practice does not resolve a concern about possible contact. Follow your care team's instructions.")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { coach.backgrounded() }
            else if phase == .active { coach.foregrounded(); planner.syncReminders() }
        }
        .onAppear {
            planner.seed(names: coach.session?.template.slots ?? ["Exchange 1", "Exchange 2", "Exchange 3", "Exchange 4"])
            planner.syncReminders()
        }
        .onChange(of: coach.session?.phase) { _, phase in
            if phase == .completed, let id = activeRoutineID { planner.complete(id); activeRoutineID = nil }
        }
        .onChange(of: developerMode) { _, enabled in
            if !enabled { coach.debugControlsEnabled = false }
        }
    }

    // MARK: Home

    @ViewBuilder private func home(_ session: RoutineSession) -> some View {
        HStack(spacing: 6) {
            SterlingRingMark().frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 0) {
                Text("Sterling").font(.system(size: 27, weight: .semibold, design: .serif))
                Text("keep it clean").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if developerMode { Text("Developer").font(.caption.bold()).foregroundStyle(SterlingStyle.accent) }
        }
        TimelineView(.periodic(from: .now, by: 60)) { context in
            routineList(at: context.date)
        }
        card {
            Label("Make room for a hands-free practice", systemImage: "waveform")
                .font(.headline)
            Text("Set your phone down with the rear camera facing your workspace. Sterling guides you by voice, with camera support and wristband feedback.")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Label(coach.voiceConfigured ? "Voice set up" : "Phone voice", systemImage: "waveform")
                Spacer()
                Label(coach.band.connected ? "Band connected" : "Band not connected", systemImage: "applewatch.radiowaves.left.and.right")
            }.font(.caption).foregroundStyle(.secondary)
            Button(coach.voiceConfigured ? "Voice and wristband settings" : "Set up your voice and wristband") { showSettings = true }
                .font(.subheadline.weight(.semibold))
        }
        if !planner.reminderMessage.isEmpty {
            Label(planner.reminderMessage, systemImage: "bell.slash").font(.footnote).foregroundStyle(.secondary)
        }
        if developerMode { developerHome }
        Text(session.template.protocolNote).font(.footnote).foregroundStyle(.secondary)
        Label("Camera images stay on your phone. Voice conversations use Cartesia when connected.", systemImage: "lock")
            .font(.footnote).foregroundStyle(.secondary)
    }

    private func routineList(at date: Date) -> some View {
        let done = planner.routines.filter { $0.completed(on: date) }.count
        let next = planner.routines.first { !$0.completed(on: date) }
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("My routines").font(.largeTitle.bold())
                    Text(date.formatted(.dateTime.weekday(.wide).month().day())).foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().stroke(SterlingStyle.accent.opacity(0.12), lineWidth: 5)
                    Circle().trim(from: 0, to: planner.routines.isEmpty ? 0 : CGFloat(done) / CGFloat(planner.routines.count))
                        .stroke(SterlingStyle.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(done)/\(planner.routines.count)").font(.subheadline.bold().monospacedDigit())
                }.frame(width: 54, height: 54)
                    .accessibilityLabel("\(done) of \(planner.routines.count) practices finished today")
            }
            Text("Your daily practice plan").font(.subheadline).foregroundStyle(.secondary)
            ForEach(planner.routines) { routine in
                routineCard(routine, done: routine.completed(on: date), next: routine.id == next?.id)
            }
            if planner.routines.isEmpty {
                Text("Add your first routine to get started.").foregroundStyle(.secondary).padding(.vertical)
            }
            Button { editingRoutine = PracticeRoutine(name: "") } label: {
                Label("Add routine", systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }

    private func routineCard(_ routine: PracticeRoutine, done: Bool, next: Bool) -> some View {
        card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    if let minutes = routine.minuteOfDay,
                       let time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) {
                        Text(time, style: .time).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    Text(routine.name).font(.title2.bold())
                }
                Spacer()
                Button { editingRoutine = routine } label: {
                    Label("Edit", systemImage: "pencil").font(.subheadline).padding(.vertical, 8)
                }.accessibilityLabel("Edit \(routine.name)")
            }
            if !routine.note.isEmpty { Text(routine.note).font(.subheadline).foregroundStyle(.secondary) }
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : (next ? "circle.inset.filled" : "circle"))
                Text(done ? "Practice finished today" : (next ? "Up next" : "Not started today"))
                if routine.reminder { Spacer(); Image(systemName: "bell").accessibilityLabel("Daily reminder enabled") }
            }.font(.subheadline).foregroundStyle(done ? SterlingStyle.accent : Color.secondary)
            Button { start(routine) } label: {
                Label(done ? "Practise again" : "Start routine", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private func returnHome() {
        coach.reset(); activeRoutineID = nil
    }

    private func start(_ routine: PracticeRoutine) {
        activeRoutineID = routine.id
        coach.selectedSlot = routine.name
        coach.start(usePhoneVoice: !coach.voiceConfigured)
    }

    @ViewBuilder private var developerHome: some View {
        Text("Developer tools").font(.title2.bold())
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                actionTile("viewfinder", "Live Guard", "Distance preview", tint: .teal) { showLiveGuard = true }
                actionTile("cpu", "Model test", "Camera without voice", tint: .purple) {
                    coach.backgrounded(); showModelDebug = true
                }
            }
            GridRow {
                actionTile("camera", "Depth test", "Camera and LiDAR", tint: .blue) { coach.backgrounded(); showCapture = true }
                actionTile("ruler", "Connectors", "Sizes and thresholds", tint: .orange) { showConnectors = true }
            }
        }
        if coach.stats.measuredSeconds >= 1 {
            SafetySummaryCard(coach: coach)
            Button("Measurement details") { showSummary = true }
        }
    }

    private func actionTile(_ symbol: String, _ title: String, _ detail: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
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
        if developerMode {
            Button { showLiveGuard = true } label: {
                Label("Open Live Guard", systemImage: "viewfinder").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large)
        }
        Text("You can say ‘pause’, ‘resume’ or ‘next step’. You don't need to touch the phone to reply.")
            .font(.footnote).foregroundStyle(.secondary)
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
            Label(coach.session?.phase == .paused ? "Paused" :
                  (coach.conversation.active ? coach.conversation.status : coach.speech.status),
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
            if developerMode {
              VStack(alignment: .leading, spacing: 6) {
                Text(coach.capture.status)
                Text(coach.observation.modelStatus).textSelection(.enabled)
                Text("\(coach.observation.detections.count) boxes · \(coach.observation.fingertips.count) fingertips · " +
                     (coach.observationAge.map { String(format: "analysed frame %.0f ms old", $0 * 1000) } ?? "waiting for analysis"))
                    .monospacedDigit()
                if !coach.displayFresh { Text("Analysis waiting, stopped or stale").foregroundStyle(.orange) }
                if coach.session?.template.detectorStatus != .experimental {
                    HStack { Text("Preview confidence"); Spacer(); Text(String(format: "%.0f%%", coach.detectionConfidence * 100)) }
                    Slider(value: $coach.detectionConfidence, in: 0.1...0.9, step: 0.05)
                    Text("Lower this to inspect weak predictions from the low-accuracy model.")
                        .foregroundStyle(.secondary)
                }
              }.font(.caption)
            }
            if !developerMode {
                Text("Experimental camera preview. It cannot confirm contact or sterility.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Finished

    @ViewBuilder private func finished(_ session: RoutineSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: session.reviewRequired ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundStyle(session.reviewRequired ? .red : .green)
            Text(session.reviewRequired ? "Practice paused for review" : (session.phase == .completed ? "Practice finished" : "Practice ended")).font(.largeTitle.bold())
            if coach.ended { Text(coach.message).foregroundStyle(.secondary) }
        }
        if !coach.ended {
            voiceCard
            Button(role: .destructive) { coach.endSession() } label: { Text("End session").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
        }
        if developerMode {
          SafetySummaryCard(coach: coach)
          ShareLink(item: coach.summaryText) {
            Label("Share summary with my care team", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
          }.buttonStyle(.bordered).controlSize(.large)
        }
        Text("This records a practice, not a completed treatment or a sterility check.")
            .font(.footnote).foregroundStyle(.secondary)
        Button {
            if session.reviewRequired { showReset = true } else { returnHome() }
        } label: {
            Label("Back to my routines", systemImage: "arrow.left").font(.headline).frame(maxWidth: .infinity)
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
                if developerMode {
                Section {
                    Button { showSettings = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showConnectors = true } } label: {
                        HStack {
                            Label("Connector tips", systemImage: "ruler")
                            Spacer()
                            Text("Blue 8 mm · Clear 13 mm").foregroundStyle(.secondary)
                        }
                    }
                    Text(coach.distanceText).font(.footnote)
                } header: { Text("Distance warnings") } footer: {
                    Text("Medium risk within \(Int(GuardThresholds.medium)) mm (pulsing band), high risk within \(Int(GuardThresholds.high)) mm (continuous band). Experimental 2D estimate; not a contact or sterility check.")
                }
                }
                Section {
                    LabeledContent("Status", value: coach.band.status)
                    if developerMode {
                    Picker("Installed firmware", selection: binding(to: coach.band, \.protocolMode)) {
                        Text("Original patterns").tag(BandProtocolMode.legacy)
                        Text("Variable intensity").tag(BandProtocolMode.intensityV2)
                    }.disabled(coach.session?.phase == .monitoring)
                    }
                    if coach.band.connected {
                        Button("Test vibration") { coach.band.set(intensity: 180) }
                            .disabled(coach.session?.phase == .monitoring)
                        Button("Disconnect", role: .destructive) { coach.band.disconnect() }
                    } else {
                        Button("Connect wristband") { coach.band.connect() }
                    }
                } header: { Text("Wristband") } footer: {
                    Text("Connect before starting. If you're testing different firmware, choose it in Developer mode.")
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
                    Toggle("Developer mode", isOn: $developerMode)
                    Text("Show camera tests, model settings, measurement details and routine debugging.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if developerMode {
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
