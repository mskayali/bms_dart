import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../models/bms_event.dart';
import '../parsers/cell_status_parser.dart';
import '../parsers/device_info_parser.dart';
import '../parsers/settings_parser.dart';
import '../protocol/constants.dart';
import '../protocol/frame_assembler.dart';
import '../protocol/request_builder.dart';

/// Manages BLE connectivity and data exchange with a JK-BMS device.
///
/// This is the primary public API for the `jk_bms` plugin. It handles:
/// - BLE scanning with JK-BMS service filter
/// - Connection lifecycle management
/// - Notification subscription and frame reassembly
/// - Request commands (cell info, device info, logbook)
/// - Parsed data streaming via [eventStream]
///
/// ## Usage
/// ```dart
/// final manager = JkBmsManager();
///
/// // Listen for events
/// manager.eventStream.listen((event) {
///   if (event is BmsCellStatusEvent) {
///     print('SOC: ${event.data.soc}%');
///   }
/// });
///
/// // Scan → connect → request data
/// manager.scanStream.listen((device) async {
///   await manager.connect(device.deviceId);
///   await manager.requestDeviceInfo();
///   await manager.requestCellStatus();
/// });
/// manager.startScan();
/// ```
class JkBmsManager {
  JkBmsManager({this.protocol = JkProtocol.jk02_32s});

  /// Protocol version to use for parsing.
  final JkProtocol protocol;

  final _eventController = StreamController<BmsEvent>.broadcast();
  final _frameAssembler = FrameAssembler();
  final _logController = StreamController<BmsLogEntry>.broadcast();

  StreamSubscription<AssembledFrame>? _frameSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Uint8List>? _notifySub;
  String? _connectedDeviceId;

  // ---------------------------------------------------------------------------
  // Public API — Streams
  // ---------------------------------------------------------------------------

  /// Stream of parsed BMS events (cell status, device info, errors, etc.).
  Stream<BmsEvent> get eventStream => _eventController.stream;

  /// Stream of raw log entries for debug display.
  Stream<BmsLogEntry> get logStream => _logController.stream;

  /// Stream of scan results filtered for JK-BMS devices.
  Stream<BleDevice> get scanStream => UniversalBle.scanStream;

  /// Currently connected device ID, or null if disconnected.
  String? get connectedDeviceId => _connectedDeviceId;

  // ---------------------------------------------------------------------------
  // Public API — Scanning
  // ---------------------------------------------------------------------------

  /// Start BLE scan filtered for JK-BMS service UUID.
  Future<void> startScan() async {
    await UniversalBle.startScan(
      scanFilter: ScanFilter(
        withServices: [kJkServiceUuid],
      ),
    );
  }

  /// Stop BLE scanning.
  Future<void> stopScan() async {
    await UniversalBle.stopScan();
  }

  // ---------------------------------------------------------------------------
  // Public API — Connection
  // ---------------------------------------------------------------------------

  /// Connect to a JK-BMS device by [deviceId].
  ///
  /// Performs the full connection sequence:
  /// 1. BLE connect
  /// 2. Discover services
  /// 3. Find FFE0/FFE1
  /// 4. Subscribe to notifications
  Future<void> connect(String deviceId) async {
    _connectedDeviceId = deviceId;

    // Listen for connection state changes
    _connectionSub?.cancel();
    _connectionSub = UniversalBle.connectionStream(deviceId).listen(
      (isConnected) {
        if (!isConnected) {
          _log('RX', 'Disconnected from $deviceId');
          _connectedDeviceId = null;
        }
      },
    );

    // Connect
    _log('TX', 'Connecting to $deviceId...');
    await UniversalBle.connect(deviceId);
    _log('RX', 'Connected to $deviceId');

    // Discover services
    _log('TX', 'Discovering services...');
    final services = await UniversalBle.discoverServices(deviceId);
    _log('RX', 'Found ${services.length} services');

    // Find the JK-BMS service and characteristic
    String? foundServiceUuid;
    String? foundCharUuid;
    for (final service in services) {
      if (service.uuid.toUpperCase().contains('FFE0')) {
        foundServiceUuid = service.uuid;
        for (final char in service.characteristics) {
          if (char.uuid.toUpperCase().contains('FFE1')) {
            foundCharUuid = char.uuid;
            break;
          }
        }
      }
    }

    if (foundServiceUuid == null || foundCharUuid == null) {
      _eventController.add(BmsErrorEvent(
        message: 'FFE1 characteristic not found on device $deviceId',
      ));
      return;
    }

    _log('RX', 'Found FFE1 characteristic');

    // Subscribe to frame assembly
    _frameSub?.cancel();
    _frameSub = _frameAssembler.frameStream.listen(_onFrameAssembled);

    // Listen for characteristic value notifications
    _notifySub?.cancel();
    _notifySub = UniversalBle.characteristicValueStream(
      deviceId,
      foundCharUuid,
    ).listen((value) {
      _logHex('RX', value);
      _frameAssembler.addChunk(value);
    });

    // Enable notifications
    _log('TX', 'Enabling notifications...');
    await UniversalBle.subscribeNotifications(
      deviceId,
      foundServiceUuid,
      foundCharUuid,
    );
    _log('RX', 'Notifications enabled');
  }

  /// Disconnect from the currently connected device.
  Future<void> disconnect() async {
    if (_connectedDeviceId != null) {
      await UniversalBle.disconnect(_connectedDeviceId!);
    }
    _connectedDeviceId = null;
    _frameSub?.cancel();
    _frameSub = null;
    _connectionSub?.cancel();
    _connectionSub = null;
    _notifySub?.cancel();
    _notifySub = null;
    _frameAssembler.reset();
  }

  // ---------------------------------------------------------------------------
  // Public API — Commands
  // ---------------------------------------------------------------------------

  /// Request cell/status data (command `0x96`).
  Future<void> requestCellStatus() async {
    final frame = cellInfoRequest();
    await _writeFrame(frame);
  }

  /// Request device info (command `0x97`).
  Future<void> requestDeviceInfo() async {
    final frame = deviceInfoRequest();
    await _writeFrame(frame);
  }

  /// Request logbook data (command `0xA1`).
  Future<void> requestLogbook() async {
    final frame = logbookRequest();
    await _writeFrame(frame);
  }

  /// Request settings data (command `0x01`, via cell-info-like read).
  ///
  /// batmon-ha sends `_jk_command(0x96)` for status and also receives
  /// settings on initial connect. Settings frames arrive as frame type `0x01`.
  /// Some firmwares automatically send settings after connect;
  /// otherwise, this method triggers a manual request.
  Future<void> requestSettings() async {
    // Settings are typically sent by BMS on connect, but can also be
    // explicitly requested. The command for settings read varies by
    // firmware; 0x96 triggers both status and settings on some models.
    final frame = buildJkRequest(kFrameTypeSettings);
    await _writeFrame(frame);
  }

  /// Send a custom request frame.
  Future<void> sendCustomRequest(
    int command, {
    int value = 0,
    int length = 0,
  }) async {
    final frame = buildJkRequest(command, value: value, length: length);
    await _writeFrame(frame);
  }

  // ---------------------------------------------------------------------------
  // Public API — Lifecycle
  // ---------------------------------------------------------------------------

  /// Release all resources.
  void dispose() {
    _frameSub?.cancel();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _frameAssembler.dispose();
    _eventController.close();
    _logController.close();
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  /// Write a request frame to the JK-BMS characteristic.
  Future<void> _writeFrame(Uint8List frame) async {
    if (_connectedDeviceId == null) {
      _eventController.add(BmsErrorEvent(
        message: 'No device connected',
      ));
      return;
    }

    _logHex('TX', frame);

    try {
      await UniversalBle.write(
        _connectedDeviceId!,
        kJkServiceUuid,
        kJkCharacteristicUuid,
        frame,
        withoutResponse: true,
      );
    } catch (e) {
      _eventController.add(BmsErrorEvent(
        message: 'Write failed: $e',
        details: e,
      ));
    }
  }

  /// Handle a fully assembled frame from the [FrameAssembler].
  void _onFrameAssembled(AssembledFrame frame) {
    if (!frame.crcValid) {
      _eventController.add(BmsErrorEvent(
        message:
            'CRC mismatch for frame type 0x${frame.frameType.toRadixString(16)}',
      ));
      // Still emit raw frame for debugging
      _eventController.add(BmsRawFrameEvent(
        frameType: frame.frameType,
        raw: frame.data,
      ));
      return;
    }

    _log(
      'RX',
      'Frame assembled: type=0x${frame.frameType.toRadixString(16)}, '
          'len=${frame.data.length}, CRC=OK',
    );

    switch (frame.frameType) {
      case kFrameTypeCellInfo:
        try {
          final status = parseCellStatus(frame.data, protocol);
          _eventController.add(BmsCellStatusEvent(data: status));
        } catch (e) {
          _eventController.add(BmsErrorEvent(
            message: 'Cell status parse error: $e',
            details: e,
          ));
        }

      case kFrameTypeDeviceInfo:
        try {
          final info = parseDeviceInfo(frame.data);
          _eventController.add(BmsDeviceInfoEvent(data: info));
        } catch (e) {
          _eventController.add(BmsErrorEvent(
            message: 'Device info parse error: $e',
            details: e,
          ));
        }

      case kFrameTypeSettings:
        try {
          final settings = parseSettings(frame.data, protocol);
          _eventController.add(BmsSettingsEvent(data: settings));
        } catch (e) {
          _eventController.add(BmsErrorEvent(
            message: 'Settings parse error: $e',
            details: e,
          ));
        }

      case kFrameTypeLogbook:
      default:
        _eventController.add(BmsRawFrameEvent(
          frameType: frame.frameType,
          raw: frame.data,
        ));
    }
  }

  void _log(String direction, String message) {
    debugPrint('[JkBMS][$direction] $message');
    _logController.add(BmsLogEntry(
      timestamp: DateTime.now(),
      direction: direction,
      message: message,
    ));
  }

  void _logHex(String direction, Uint8List data) {
    final hex = data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    _log(direction, '[${data.length} bytes] $hex');
  }
}

/// A single log entry for debug display.
class BmsLogEntry {
  const BmsLogEntry({
    required this.timestamp,
    required this.direction,
    required this.message,
  });

  final DateTime timestamp;

  /// "TX" or "RX".
  final String direction;

  final String message;

  @override
  String toString() {
    final ts = '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    return '[$ts][$direction] $message';
  }
}
