import CoreBluetooth
import Combine
import Foundation

final class BandClient: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published private(set) var status = "Band disconnected"
    @Published private(set) var connected = false
    @Published var protocolMode = BandProtocolMode(rawValue: UserDefaults.standard.string(forKey: "sterling.bandProtocol") ?? "legacy") ?? .legacy {
        willSet { if newValue != protocolMode { disconnect() } }
        didSet { UserDefaults.standard.set(protocolMode.rawValue, forKey: "sterling.bandProtocol") }
    }
    @Published private(set) var writesSubmitted = 0
    @Published private(set) var lastCommandDescription = "No command sent"
    private var keepConnected = false
    private var lastConnectionAttempt = -Double.infinity
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private let service = CBUUID(string: "7a1e0001-3c5d-4b8a-9f21-6d2c8e4b1a00")
    private var commandID: CBUUID {
        CBUUID(string: protocolMode == .legacy
               ? "7a1e0002-3c5d-4b8a-9f21-6d2c8e4b1a00"
               : "7a1e0003-3c5d-4b8a-9f21-6d2c8e4b1a00")
    }
    private var desired = Data([83])
    private var lastSent: Data?
    private var validUntil = 0.0
    private var timer: Timer?
    private var scanTimer: Timer?

    override init() { super.init() } // Bluetooth permission is requested only on Connect.
    func beginRoutineConnection() {
        keepConnected = true; lastConnectionAttempt = -Double.infinity
        maintainRoutineConnection()
    }
    func maintainRoutineConnection() {
        // Pair/authorize once during setup. A routine never launches a new permission prompt.
        guard keepConnected, !connected, peripheral == nil, CBManager.authorization == .allowedAlways,
              ProcessInfo.processInfo.systemUptime - lastConnectionAttempt >= 10 else { return }
        connect()
    }
    func endRoutineConnection() { keepConnected = false; stop() }
    var diagnostics: String {
        "BLE protocol: \(protocolMode.rawValue); writes submitted: \(writesSubmitted); last command: \(lastCommandDescription). Writes have no motor acknowledgement."
    }
    func connect() {
        lastConnectionAttempt = ProcessInfo.processInfo.systemUptime
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else if central.state == .poweredOn { scan() }
    }
    private func scan() {
        guard peripheral == nil else { return }
        status = "Looking for DialysisBand…"
        central.scanForPeripherals(withServices: [service])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.central.stopScan()
            if self?.connected == false { self?.status = "Band not found; check power and retry Connect." }
        }
    }
    func disconnect() {
        keepConnected = false
        stop()
        scanTimer?.invalidate(); scanTimer = nil
        central?.stopScan()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        self.peripheral = nil; characteristic = nil; connected = false
        timer?.invalidate(); timer = nil
        status = "Band disconnected"
    }
    func set(intensity: UInt8, suspected: Bool = false) {
        desired = Data(BandEncoding.payload(intensity: intensity, suspected: suspected, mode: protocolMode))
        validUntil = ProcessInfo.processInfo.systemUptime + 0.25
        flush()
    }
    func stop() {
        desired = Data(BandEncoding.payload(intensity: 0, suspected: false, mode: protocolMode))
        validUntil = 0
        flush()
    }
    private func flush() {
        guard let peripheral, let characteristic, connected else { return }
        let off = Data(BandEncoding.payload(intensity: 0, suspected: false, mode: protocolMode))
        let next = ProcessInfo.processInfo.systemUptime <= validUntil ? desired : off
        guard protocolMode == .intensityV2 || next != lastSent else { return }
        // Bound host-side writes: no application queue and only the current command survives.
        guard peripheral.canSendWriteWithoutResponse else { return }
        peripheral.writeValue(next, for: characteristic, type: .withoutResponse)
        lastSent = next
        writesSubmitted += 1
        if next == off { lastCommandDescription = "Stop" }
        else if protocolMode == .legacy { lastCommandDescription = next == Data([69]) ? "High-risk pattern (E)" : "Medium-risk pattern (W)" }
        else { lastCommandDescription = "Intensity \(next.last ?? 0) (v2)" }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { scan() }
        else {
            timer?.invalidate(); timer = nil
            scanTimer?.invalidate(); scanTimer = nil
            peripheral = nil; characteristic = nil; connected = false; lastSent = nil
            validUntil = 0
            status = "Bluetooth unavailable or permission denied"
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        central.stopScan(); scanTimer?.invalidate()
        self.peripheral = peripheral
        peripheral.delegate = self
        status = "Connecting to band…"
        central.connect(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        peripheral.discoverServices([service])
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == self.service }) else {
            disconnect(); status = "Band service unavailable"; return
        }
        peripheral.discoverCharacteristics([commandID], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard self.peripheral?.identifier == peripheral.identifier else { return }
        guard error == nil, let found = service.characteristics?.first(where: { $0.uuid == commandID }),
              found.properties.contains(.writeWithoutResponse) else {
            disconnect(); status = "Selected firmware protocol unavailable"; return
        }
        characteristic = found; connected = true; lastSent = nil
        status = protocolMode == .legacy ? "Band connected: fixed patterns" : "Band connected: intensity v2"
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.flush() }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { flush() }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let retry = keepConnected
        disconnect(); keepConnected = retry
        status = retry ? "Band connection failed; retrying during the routine" : "Band connection failed; retry Connect"
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Retry a previously authorized band during a routine; never replay an old intensity.
        if self.peripheral?.identifier == peripheral.identifier {
            self.peripheral = nil; characteristic = nil; connected = false
            timer?.invalidate(); timer = nil; lastSent = nil; validUntil = 0
            status = "Band lost; audio and display remain available"
        }
    }
}
