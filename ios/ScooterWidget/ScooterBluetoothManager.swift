import CoreBluetooth
import Foundation

/// Manages Bluetooth communication with the unu scooter from widget extension
class ScooterBluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // MARK: - Constants

    /// Service UUID for scooter commands
    static let commandServiceUUID = CBUUID(string: "9a590000-6e67-5d0d-aab9-ad9126b66f91")

    /// Characteristic UUID for writing commands
    static let commandCharacteristicUUID = CBUUID(string: "9a590001-6e67-5d0d-aab9-ad9126b66f91")

    /// State service UUID for reading scooter state
    static let stateServiceUUID = CBUUID(string: "9a590020-6e67-5d0d-aab9-ad9126b66f91")

    /// Handlebar characteristic UUID
    static let handlebarCharacteristicUUID = CBUUID(string: "9a590023-6e67-5d0d-aab9-ad9126b66f91")

    // MARK: - Properties

    private var centralManager: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var handlebarCharacteristic: CBCharacteristic?

    private var targetScooterUUID: UUID?
    private var pendingCommand: String?
    private var completion: ((Bool, String?) -> Void)?

    private var connectionTimeout: Timer?
    private var operationTimeout: Timer?

    private let timeoutDuration: TimeInterval = 15.0

    // MARK: - Singleton

    static let shared = ScooterBluetoothManager()

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Execute a command on the scooter
    /// - Parameters:
    ///   - command: The command to send ("lock" or "unlock")
    ///   - completion: Callback with success status and optional error message
    func executeCommand(_ command: String, completion: @escaping (Bool, String?) -> Void) {
        // Get the saved scooter ID from UserDefaults
        guard let prefs = UserDefaults(suiteName: "group.de.freal.unustasis") else {
            completion(false, "Cannot access app group")
            return
        }

        guard let scooterIdString = prefs.string(forKey: "lastConnectedScooterId") else {
            completion(false, "No saved scooter found")
            return
        }

        guard let scooterUUID = UUID(uuidString: scooterIdString) else {
            completion(false, "Invalid scooter ID format")
            return
        }

        self.targetScooterUUID = scooterUUID
        self.pendingCommand = command == "lock" ? "scooter:state lock" : "scooter:state unlock"
        self.completion = completion

        // Initialize Central Manager if needed
        if centralManager == nil {
            centralManager = CBCentralManager(
                delegate: self, queue: DispatchQueue.main,
                options: [
                    CBCentralManagerOptionShowPowerAlertKey: false
                ])
        } else if centralManager.state == .poweredOn {
            startScanning()
        }
        // If not powered on yet, we'll start scanning in centralManagerDidUpdateState

        // Set connection timeout
        connectionTimeout = Timer.scheduledTimer(withTimeInterval: timeoutDuration, repeats: false)
        { [weak self] _ in
            self?.handleTimeout()
        }
    }

    // MARK: - Private Methods

    private func startScanning() {
        guard let targetUUID = targetScooterUUID else { return }

        // Try to retrieve the peripheral directly if we know its UUID
        let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: [targetUUID])

        if let peripheral = knownPeripherals.first {
            // Found the peripheral, connect directly
            self.targetPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        } else {
            // Need to scan for the peripheral
            centralManager.scanForPeripherals(
                withServices: [ScooterBluetoothManager.commandServiceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }
    }

    private func handleTimeout() {
        cleanup()
        completion?(false, "Connection timeout")
        completion = nil
    }

    private func cleanup() {
        connectionTimeout?.invalidate()
        connectionTimeout = nil
        operationTimeout?.invalidate()
        operationTimeout = nil

        centralManager?.stopScan()

        if let peripheral = targetPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }

        targetPeripheral = nil
        commandCharacteristic = nil
        handlebarCharacteristic = nil
    }

    private func sendCommand() {
        guard let characteristic = commandCharacteristic,
            let peripheral = targetPeripheral,
            let command = pendingCommand,
            let data = command.data(using: .ascii)
        else {
            completion?(false, "Not ready to send command")
            cleanup()
            return
        }

        // Set operation timeout
        operationTimeout = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) {
            [weak self] _ in
            self?.cleanup()
            self?.completion?(false, "Command timeout")
            self?.completion = nil
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func updateWidgetState(locked: Bool?) {
        guard let prefs = UserDefaults(suiteName: "group.de.freal.unustasis") else { return }

        if let locked = locked {
            prefs.set(locked, forKey: "locked")
        }
        prefs.set(false, forKey: "scanning")
        prefs.synchronize()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if pendingCommand != nil {
                startScanning()
            }
        case .poweredOff:
            completion?(false, "Bluetooth is turned off")
            cleanup()
        case .unauthorized:
            completion?(false, "Bluetooth permission denied")
            cleanup()
        case .unsupported:
            completion?(false, "Bluetooth not supported")
            cleanup()
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        // Check if this is our target scooter
        if peripheral.identifier == targetScooterUUID {
            centralManager.stopScan()
            targetPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Discover the command service
        peripheral.discoverServices([
            ScooterBluetoothManager.commandServiceUUID,
            ScooterBluetoothManager.stateServiceUUID,
        ])
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        completion?(false, "Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        cleanup()
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        // Disconnected after command was sent - this is expected
        if commandCharacteristic != nil {
            // Command was likely sent successfully
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            completion?(false, "Service discovery failed: \(error!.localizedDescription)")
            cleanup()
            return
        }

        for service in peripheral.services ?? [] {
            if service.uuid == ScooterBluetoothManager.commandServiceUUID {
                peripheral.discoverCharacteristics(
                    [ScooterBluetoothManager.commandCharacteristicUUID],
                    for: service
                )
            } else if service.uuid == ScooterBluetoothManager.stateServiceUUID {
                peripheral.discoverCharacteristics(
                    [ScooterBluetoothManager.handlebarCharacteristicUUID],
                    for: service
                )
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        guard error == nil else {
            completion?(false, "Characteristic discovery failed: \(error!.localizedDescription)")
            cleanup()
            return
        }

        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == ScooterBluetoothManager.commandCharacteristicUUID {
                commandCharacteristic = characteristic
            } else if characteristic.uuid == ScooterBluetoothManager.handlebarCharacteristicUUID {
                handlebarCharacteristic = characteristic
            }
        }

        // If we have the command characteristic, send the command
        if commandCharacteristic != nil {
            sendCommand()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        operationTimeout?.invalidate()
        operationTimeout = nil

        if let error = error {
            completion?(false, "Write failed: \(error.localizedDescription)")
        } else {
            // Update widget state based on command sent
            let isLockCommand =
                pendingCommand?.contains("lock") == true
                && pendingCommand?.contains("unlock") == false
            updateWidgetState(locked: isLockCommand)
            completion?(true, nil)
        }

        cleanup()
        completion = nil
    }
}
