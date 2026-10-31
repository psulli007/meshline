//
// MeshtasticRadioService.swift
// Meshline
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//
// Optional LoRa link: pairs one Meshtastic radio over Bluetooth LE and uses
// it as a long range pipe for Meshline frames (PRIVATE_APP port, broadcast).
// Frames already carry Meshline's own end to end encryption; the radio's
// channel key adds a second layer over the air.
//

import BitFoundation
import BitLogger
import Combine
import CoreBluetooth
import Foundation

struct DiscoveredRadio: Identifiable, Equatable {
    let id: UUID
    let name: String
    let rssi: Int
}

enum RadioLinkState: Equatable {
    case idle
    case bluetoothOff
    case scanning
    case connecting(String)
    case configuring(String)
    case connected(String)
    case disconnected(String)

    var label: String {
        switch self {
        case .idle: return "No radio paired"
        case .bluetoothOff: return "Bluetooth is off or not allowed"
        case .scanning: return "Looking for Meshtastic radios..."
        case .connecting(let name): return "Connecting to \(name)..."
        case .configuring(let name): return "Setting up \(name)..."
        case .connected(let name): return "Connected to \(name)"
        case .disconnected(let name): return "\(name) is out of range. Reconnecting when it is back."
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

final class MeshtasticRadioService: NSObject, ObservableObject {
    static let shared = MeshtasticRadioService()

    static let savedRadioKey = "meshline.lora.radioID"
    static let savedRadioNameKey = "meshline.lora.radioName"

    @Published private(set) var state: RadioLinkState = .idle
    @Published private(set) var discovered: [DiscoveredRadio] = []
    @Published private(set) var pairedRadioName: String?
    @Published private(set) var framesSent: Int = 0
    @Published private(set) var framesReceived: Int = 0

    /// Called on the service queue with each reassembled, decoded packet.
    var onPacket: ((BitchatPacket) -> Void)? {
        get { callbackLock.lock(); defer { callbackLock.unlock() }; return _onPacket }
        set { callbackLock.lock(); _onPacket = newValue; callbackLock.unlock() }
    }

    private let callbackLock = NSLock()
    private var _onPacket: ((BitchatPacket) -> Void)?
    private let readyLock = NSLock()
    private var _isReady = false

    private let queue = DispatchQueue(label: "meshline.lora")
    private let defaults: UserDefaults

    // Queue confined.
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var toRadio: CBCharacteristic?
    private var fromRadio: CBCharacteristic?
    private var fromNum: CBCharacteristic?
    private var wantsScan = false
    private var draining = false
    private var configID: UInt32 = 0
    private var myNodeNum: UInt32?
    private var reassembler = LoRaReassembler()
    private let policyLock = NSLock()
    private var policy = LoRaForwardPolicy()
    private var discoveredByID: [UUID: DiscoveredRadio] = [:]

    private static let serviceID = CBUUID(string: MeshtasticBLE.serviceUUID)
    private static let toRadioID = CBUUID(string: MeshtasticBLE.toRadioUUID)
    private static let fromRadioID = CBUUID(string: MeshtasticBLE.fromRadioUUID)
    private static let fromNumID = CBUUID(string: MeshtasticBLE.fromNumUUID)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        pairedRadioName = defaults.string(forKey: Self.savedRadioNameKey)
    }

    private var savedRadioID: UUID? {
        defaults.string(forKey: Self.savedRadioKey).flatMap(UUID.init(uuidString:))
    }

    var isReady: Bool {
        readyLock.lock(); defer { readyLock.unlock() }
        return _isReady
    }

    private func setReady(_ ready: Bool) {
        readyLock.lock(); _isReady = ready; readyLock.unlock()
    }

    // MARK: - Public controls (any thread)

    /// Reconnects to a previously paired radio. Does nothing if none.
    func resumeSavedRadioIfNeeded() {
        queue.async { [weak self] in
            guard let self, self.savedRadioID != nil else { return }
            self.ensureCentral()
            self.connectSavedIfPossible()
        }
    }

    func startScan() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsScan = true
            self.discoveredByID = [:]
            self.publishDiscovered()
            self.ensureCentral()
            self.beginScanIfPossible()
        }
    }

    func stopScan() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsScan = false
            self.central?.stopScan()
            if case .scanning = self.currentStateGuess { self.publish(state: self.restingState()) }
        }
    }

    func pair(_ radio: DiscoveredRadio) {
        queue.async { [weak self] in
            guard let self else { return }
            self.defaults.set(radio.id.uuidString, forKey: Self.savedRadioKey)
            self.defaults.set(radio.name, forKey: Self.savedRadioNameKey)
            DispatchQueue.main.async { self.pairedRadioName = radio.name }
            self.wantsScan = false
            self.central?.stopScan()
            self.disconnectCurrent()
            self.connectSavedIfPossible()
        }
    }

    /// Forgets the radio. iOS keeps the system Bluetooth bond; the user can
    /// remove it in Settings > Bluetooth.
    func unpair() {
        queue.async { [weak self] in
            guard let self else { return }
            self.defaults.removeObject(forKey: Self.savedRadioKey)
            self.defaults.removeObject(forKey: Self.savedRadioNameKey)
            self.disconnectCurrent()
            DispatchQueue.main.async { self.pairedRadioName = nil }
            self.publish(state: .idle)
        }
    }

    /// Stops radio I/O (panic wipe or service shutdown) without forgetting.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsScan = false
            self.central?.stopScan()
            self.disconnectCurrent()
        }
    }

    /// Non-blocking. Returns true if the frame was admitted for LoRa.
    @discardableResult
    func sendIfAdmitted(_ packet: BitchatPacket) -> Bool {
        guard isReady else { return false }
        guard let frame = packet.toBinaryData(padding: false),
              let chunks = LoRaFraming.split(frame, messageID: UInt32.random(in: 1...UInt32.max)) else {
            return false
        }
        policyLock.lock()
        let admitted = policy.admit(packet, chunkCount: chunks.count)
        policyLock.unlock()
        guard admitted else { return false }
        queue.async { [weak self] in
            guard let self, let peripheral = self.peripheral, let toRadio = self.toRadio else { return }
            for chunk in chunks {
                let message = MeshtasticMessages.broadcastPrivateApp(
                    payload: chunk,
                    packetID: UInt32.random(in: 1...UInt32.max)
                )
                peripheral.writeValue(message, for: toRadio, type: .withResponse)
            }
            DispatchQueue.main.async { self.framesSent += 1 }
        }
        return true
    }

    // MARK: - Queue confined helpers

    private var currentStateGuess: RadioLinkState = .idle

    private func publish(state newState: RadioLinkState) {
        currentStateGuess = newState
        DispatchQueue.main.async { self.state = newState }
    }

    private func publishDiscovered() {
        let list = discoveredByID.values.sorted { $0.rssi > $1.rssi }
        DispatchQueue.main.async { self.discovered = list }
    }

    private func restingState() -> RadioLinkState {
        if let name = defaults.string(forKey: Self.savedRadioNameKey) {
            return peripheral == nil ? .disconnected(name) : .connecting(name)
        }
        return .idle
    }

    private func ensureCentral() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: queue)
    }

    private func beginScanIfPossible() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [Self.serviceID], options: nil)
        publish(state: .scanning)
    }

    private func connectSavedIfPossible() {
        guard let central, central.state == .poweredOn, let id = savedRadioID else { return }
        let name = defaults.string(forKey: Self.savedRadioNameKey) ?? "radio"
        guard let target = central.retrievePeripherals(withIdentifiers: [id]).first else {
            // Not known to the system yet: scan and connect on discovery.
            wantsScan = true
            beginScanIfPossible()
            return
        }
        peripheral = target
        target.delegate = self
        publish(state: .connecting(name))
        // iOS connect requests do not time out; this waits until in range.
        central.connect(target, options: nil)
    }

    private func disconnectCurrent() {
        setReady(false)
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        toRadio = nil
        fromRadio = nil
        fromNum = nil
        draining = false
        myNodeNum = nil
        reassembler = LoRaReassembler()
    }

    private func drainFromRadio() {
        guard let peripheral, let fromRadio else { return }
        draining = true
        peripheral.readValue(for: fromRadio)
    }

    private func handleFromRadio(_ data: Data) {
        guard let message = MeshtasticMessages.decodeFromRadio(data) else { return }
        switch message {
        case .myNodeNum(let num):
            myNodeNum = num
        case .configComplete(let id):
            guard id == configID else { return }
            setReady(true)
            let name = defaults.string(forKey: Self.savedRadioNameKey) ?? peripheral?.name ?? "radio"
            publish(state: .connected(name))
            SecureLogger.info("📻 LoRa radio ready", category: .session)
        case .privateApp(let from, let payload):
            guard from != myNodeNum, let chunk = LoRaFraming.parse(payload) else { return }
            guard let frame = reassembler.add(chunk, from: from),
                  let packet = BinaryProtocol.decode(frame) else { return }
            policyLock.lock()
            policy.noteReceived(packet)
            policyLock.unlock()
            DispatchQueue.main.async { self.framesReceived += 1 }
            onPacket?(packet)
        case .other:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension MeshtasticRadioService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            setReady(false)
            if central.state != .unknown && central.state != .resetting {
                publish(state: .bluetoothOff)
            }
            return
        }
        if wantsScan { beginScanIfPossible() }
        if peripheral == nil { connectSavedIfPossible() }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name
            ?? "Meshtastic radio"
        if peripheral.identifier == savedRadioID, self.peripheral == nil {
            wantsScan = false
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            publish(state: .connecting(name))
            central.connect(peripheral, options: nil)
            return
        }
        discoveredByID[peripheral.identifier] = DiscoveredRadio(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        publishDiscovered()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        publish(state: .configuring(defaults.string(forKey: Self.savedRadioNameKey) ?? "radio"))
        peripheral.discoverServices([Self.serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        SecureLogger.warning("📻 LoRa radio connect failed: \(error?.localizedDescription ?? "unknown")", category: .session)
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        setReady(false)
        toRadio = nil
        fromRadio = nil
        fromNum = nil
        draining = false
        guard savedRadioID != nil else { return }
        publish(state: .disconnected(defaults.string(forKey: Self.savedRadioNameKey) ?? "radio"))
        central.connect(peripheral, options: nil)
    }
}

// MARK: - CBPeripheralDelegate

extension MeshtasticRadioService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral,
              let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else { return }
        peripheral.discoverCharacteristics([Self.toRadioID, Self.fromRadioID, Self.fromNumID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.toRadioID: toRadio = characteristic
            case Self.fromRadioID: fromRadio = characteristic
            case Self.fromNumID: fromNum = characteristic
            default: break
            }
        }
        guard let toRadio, fromRadio != nil else {
            SecureLogger.warning("📻 Device is not a compatible Meshtastic radio", category: .session)
            return
        }
        if let fromNum { peripheral.setNotifyValue(true, for: fromNum) }
        // Ask for the config stream; the reply ends with config_complete_id.
        // The first encrypted read triggers the iOS pairing PIN prompt.
        configID = UInt32.random(in: 1...UInt32.max)
        peripheral.writeValue(MeshtasticMessages.wantConfig(id: configID), for: toRadio, type: .withResponse)
        drainFromRadio()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if characteristic.uuid == Self.fromNumID {
            if !draining { drainFromRadio() }
            return
        }
        guard characteristic.uuid == Self.fromRadioID else { return }
        if let error {
            draining = false
            SecureLogger.warning("📻 LoRa radio read failed: \(error.localizedDescription)", category: .session)
            return
        }
        guard let value = characteristic.value, !value.isEmpty else {
            draining = false
            return
        }
        handleFromRadio(value)
        drainFromRadio()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            SecureLogger.debug("📻 LoRa radio write failed: \(error.localizedDescription)", category: .session)
        }
    }
}
