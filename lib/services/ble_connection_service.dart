import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../infrastructure/characteristic_repository.dart';

/// Service responsible for managing BLE connections to scooters
class BLEConnectionService {
  final log = Logger('BLEConnectionService');
  
  BluetoothDevice? _connectedDevice;
  String? _connectedScooterId;
  CharacteristicRepository? _characteristicRepository;
  
  final StreamController<String?> _connectionController = StreamController<String?>.broadcast();
  
  /// Stream of connected scooter IDs (null when disconnected)
  Stream<String?> get connectionStream => _connectionController.stream;
  
  /// Currently connected BLE device
  BluetoothDevice? get connectedDevice => _connectedDevice;
  
  /// ID of currently connected scooter
  String? get connectedScooterId => _connectedScooterId;
  
  /// Characteristic repository for the connected device
  CharacteristicRepository? get characteristicRepository => _characteristicRepository;
  
  /// Check if connected to a specific scooter
  bool isConnectedTo(String scooterId) => _connectedScooterId == scooterId;
  
  /// Check if any scooter is connected
  bool get isConnected => _connectedDevice != null && _connectedDevice!.isConnected;
  
  /// Attempt to connect to a scooter
  Future<bool> attemptConnection(String scooterId) async {
    try {
      log.info("Attempting BLE connection to scooter: $scooterId");
      
      // Disconnect from current device if connected to different scooter
      if (_connectedScooterId != null && _connectedScooterId != scooterId) {
        await disconnect();
      }
      
      // If already connected to this scooter, return true
      if (_connectedScooterId == scooterId && isConnected) {
        log.info("Already connected to scooter: $scooterId");
        return true;
      }
      
      BluetoothDevice device = BluetoothDevice.fromId(scooterId);
      
      // Try to connect
      await device.connect(timeout: const Duration(seconds: 10));
      
      // Set up characteristics
      await _setupCharacteristics(device);
      
      // Store connection info
      _connectedDevice = device;
      _connectedScooterId = scooterId;
      
      // Listen for disconnection
      device.connectionState.listen((BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });
      
      log.info("Successfully connected to scooter: $scooterId");
      _connectionController.add(scooterId);
      
      return true;
    } catch (e, stack) {
      log.warning("Failed to connect to scooter $scooterId", e, stack);
      _connectionController.add(null);
      return false;
    }
  }
  
  /// Disconnect from current scooter
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (e) {
        log.warning("Error disconnecting from BLE device", e);
      }
    }
    
    _handleDisconnection();
  }
  
  /// Handle disconnection cleanup
  void _handleDisconnection() {
    log.info("BLE device disconnected");
    _connectedDevice = null;
    _connectedScooterId = null;
    _characteristicRepository = null;
    _connectionController.add(null);
  }
  
  /// Set up BLE characteristics for the connected device
  Future<void> _setupCharacteristics(BluetoothDevice device) async {
    // This is a placeholder - the actual characteristic setup logic
    // should be moved from ScooterService to here
    _characteristicRepository = CharacteristicRepository(device);
    
    // TODO: Move characteristic discovery and setup logic here
    // from ScooterService.setUpCharacteristics()
    await _characteristicRepository!.findAll();
  }
  
  /// Dispose of the service
  void dispose() {
    _connectionController.close();
    disconnect();
  }
}