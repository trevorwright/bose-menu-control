import CoreBluetooth
import Foundation

@MainActor
protocol BoseBLEConnectionDelegate: AnyObject {
    func connection(_ connection: BoseBLEConnection, didChangePhase phase: BoseBLEConnection.Phase)
    /// Every well-formed BMAP frame the headphones send, whether or not it answers a request.
    func connection(_ connection: BoseBLEConnection, didReceive packet: BMAPPacket)
}

/// Finds Bose headphones advertising the BMAP BLE service, keeps a connection open, and exchanges BMAP
/// packets one at a time over the secure BMAP characteristic.
@MainActor
final class BoseBLEConnection: NSObject {
    enum Phase: Equatable {
        case bluetoothUnavailable(String)
        case searching
        case connecting(name: String?)
        case ready(name: String?)
    }

    static let serviceUUID = CBUUID(string: "0000FEBE-0000-1000-8000-00805F9B34FB")
    static let secureCharacteristicUUID = CBUUID(string: "C65B8F2F-AEE2-4C89-B758-BC4892D6F2D8")

    weak var delegate: BoseBLEConnectionDelegate?

    private(set) var phase: Phase = .searching {
        didSet {
            guard phase != oldValue else { return }
            Log.bluetooth.notice("Phase: \(String(describing: self.phase), privacy: .public)")
            delegate?.connection(self, didChangePhase: phase)
        }
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var assembler = BLESegmentAssembler()

    private var queueTail: Task<Void, Never>?
    private var pending: PendingExchange?

    private final class PendingExchange {
        let request: BMAPPacket
        private var continuation: CheckedContinuation<BMAPPacket, Error>?

        init(request: BMAPPacket) { self.request = request }

        func arm(_ continuation: CheckedContinuation<BMAPPacket, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<BMAPPacket, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var peripheralName: String? { peripheral?.name }

    // MARK: Requests

    /// Sends a packet and waits for its reply. Requests are serialized so replies cannot be confused.
    func exchange(_ request: BMAPPacket, timeout: Duration = .seconds(3)) async throws -> BMAPPacket {
        let previous = queueTail
        let task = Task<BMAPPacket, Error> {
            await previous?.value
            return try await performExchange(request, timeout: timeout)
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    func get(_ function: BMAPFunction, payload: [UInt8] = []) async throws -> [UInt8] {
        try await exchange(BMAPPacket(function, operation: .get, payload: payload)).payload
    }

    private func performExchange(_ request: BMAPPacket, timeout: Duration) async throws -> BMAPPacket {
        guard case .ready = phase, let peripheral, let characteristic else { throw BMAPError.notConnected }

        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        if writeType == .withoutResponse {
            var attempts = 0
            while !peripheral.canSendWriteWithoutResponse && attempts < 50 {
                attempts += 1
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        guard case .ready = phase else { throw BMAPError.notConnected }

        let exchange = PendingExchange(request: request)
        pending = exchange
        defer { if pending === exchange { pending = nil } }

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            exchange.finish(.failure(BMAPError.timeout(request.function)))
        }
        defer { timeoutTask.cancel() }

        // Single-segment BLE header byte, then the BMAP frame.
        Log.bluetooth.debug("TX \(request.frame.hexString, privacy: .public)")
        peripheral.writeValue(Data([0] + request.frame), for: characteristic, type: writeType)

        return try await withCheckedThrowingContinuation { continuation in
            exchange.arm(continuation)
        }
    }

    private func failPending(_ error: Error) {
        pending?.finish(.failure(error))
        pending = nil
    }

    // MARK: Connection lifecycle

    private func beginSearch() {
        guard let central, central.state == .poweredOn else { return }
        phase = .searching
        if let connected = central.retrieveConnectedPeripherals(withServices: [Self.serviceUUID]).first {
            connect(to: connected)
        } else {
            central.scanForPeripherals(withServices: [Self.serviceUUID])
        }
    }

    private func connect(to target: CBPeripheral) {
        guard let central else { return }
        Log.bluetooth.notice("Connecting to \(target.name ?? "unnamed", privacy: .public)")
        central.stopScan()
        peripheral = target
        target.delegate = self
        phase = .connecting(name: target.name)
        central.connect(target)
    }

    private func dropConnection(retry: Bool) {
        characteristic = nil
        assembler.reset()
        failPending(BMAPError.notConnected)
        guard let central, central.state == .poweredOn else { return }
        if retry, let peripheral {
            // A pending connect completes as soon as the headphones advertise again.
            phase = .searching
            central.connect(peripheral)
        } else {
            peripheral = nil
            beginSearch()
        }
    }

    private func handle(frame: [UInt8]) {
        guard let packet = BMAPPacket(frame: frame) else {
            Log.bluetooth.error("Malformed frame \(frame.hexString, privacy: .public)")
            return
        }
        Log.bluetooth.debug("RX \(frame.hexString, privacy: .public)")
        if let pending, packet.isReply(to: pending.request) {
            self.pending = nil
            if packet.operation == .error {
                pending.finish(.failure(BMAPError.deviceError(packet.function, code: packet.payload.first)))
            } else {
                pending.finish(.success(packet))
            }
        }
        delegate?.connection(self, didReceive: packet)
    }
}

extension BoseBLEConnection: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Log.bluetooth.notice("Bluetooth state \(central.state.rawValue) authorization \(CBManager.authorization.rawValue)")
        switch central.state {
        case .poweredOn:
            beginSearch()
        case .poweredOff:
            peripheral = nil
            dropConnection(retry: false)
            phase = .bluetoothUnavailable("Bluetooth is turned off.")
        case .unauthorized:
            phase = .bluetoothUnavailable("Allow Bluetooth access for Bose Menu Control in System Settings > Privacy & Security > Bluetooth.")
        case .unsupported:
            phase = .bluetoothUnavailable("This Mac does not support Bluetooth Low Energy.")
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil || self.peripheral?.identifier == peripheral.identifier else { return }
        connect(to: peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        phase = .connecting(name: peripheral.name)
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Log.bluetooth.error("Connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        self.peripheral = nil
        dropConnection(retry: false)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Log.bluetooth.notice("Disconnected: \(error?.localizedDescription ?? "no error", privacy: .public)")
        dropConnection(retry: true)
    }
}

extension BoseBLEConnection: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        peripheral.discoverCharacteristics([Self.secureCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil,
              let item = service.characteristics?.first(where: { $0.uuid == Self.secureCharacteristicUUID }),
              item.properties.contains(.notify),
              item.properties.contains(.write) || item.properties.contains(.writeWithoutResponse) else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        characteristic = item
        peripheral.setNotifyValue(true, for: item)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.isNotifying else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        assembler.reset()
        phase = .ready(name: peripheral.name)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard invalidatedServices.contains(where: { $0.uuid == Self.serviceUUID }) else { return }
        characteristic = nil
        phase = .connecting(name: peripheral.name)
        failPending(BMAPError.notConnected)
        peripheral.discoverServices([Self.serviceUUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            failPending(BMAPError.writeFailed(error.localizedDescription))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        if let frame = assembler.consume(data) {
            handle(frame: frame)
        }
    }
}

private extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
