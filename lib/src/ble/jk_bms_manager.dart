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
  String? _foundServiceUuid;
  String? _foundWriteCharUuid;
  String? _foundNotifyCharUuid;

  // ---------------------------------------------------------------------------
  // UUID variant matching
  // ---------------------------------------------------------------------------

  /// Known JK-BMS service/characteristic UUID patterns.
  ///
  /// Different JK-BMS models use different UUIDs:
  /// - Classic: FFE0 → FFE1 (single char for write+notify)
  /// - WE24300/newer: FF00 → FF01 (notify) + FF02 (write)
  /// - FFF0 variant: FFF0 → FFF1 (notify) + FFF2 (write)
  static const _servicePatterns = [
    // Pattern: serviceContains, notifyContains, writeContains
    ('FFE0', 'FFE1', 'FFE1'), // Classic JK-BMS (same char for both)
    ('FF00', 'FF01', 'FF02'), // WE24300 / newer models
    ('FFF0', 'FFF1', 'FFF2'), // FFF0 variant
  ];

  /// Attempt to find a matching service/characteristic set from
  /// the discovered services.
  ({String service, String notifyChar, String writeChar})? _findJkService(
    List<BleService> services,
  ) {
    for (final (svcPattern, notifyPattern, writePattern) in _servicePatterns) {
      for (final service in services) {
        final svcUuid = service.uuid.toUpperCase();
        if (!svcUuid.contains(svcPattern)) continue;

        String? notifyUuid;
        String? writeUuid;

        for (final char in service.characteristics) {
          final charUuid = char.uuid.toUpperCase();
          final props = char.properties;

          if (charUuid.contains(notifyPattern) &&
              props.contains(CharacteristicProperty.notify)) {
            notifyUuid = char.uuid;
          }
          if (charUuid.contains(writePattern) &&
              (props.contains(CharacteristicProperty.write) ||
                  props.contains(CharacteristicProperty.writeWithoutResponse))) {
            writeUuid = char.uuid;
          }
        }

        if (notifyUuid != null && writeUuid != null) {
          debugPrint(
            '[JK-BMS] Matched pattern $svcPattern: '
            'service=${service.uuid}, notify=$notifyUuid, write=$writeUuid',
          );
          return (
            service: service.uuid,
            notifyChar: notifyUuid,
            writeChar: writeUuid,
          );
        }
      }
    }
    return null;
  }

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

  /// Notify characteristic UUID discovered during connection.
  /// Useful for debug display.
  String? get connectedNotifyCharUuid => _foundNotifyCharUuid;

  /// Write characteristic UUID discovered during connection.
  String? get connectedWriteCharUuid => _foundWriteCharUuid;

  // ---------------------------------------------------------------------------
  // Public API — Scanning
  // ---------------------------------------------------------------------------

  /// Start BLE scan for all nearby devices.
  ///
  /// JK-BMS devices typically do **not** advertise the FFE0 service UUID
  /// in their advertisement packets — the service is only discoverable
  /// after connecting. Therefore we scan without a service filter.
  /// Device names usually start with `JK-` or `JK_`.
  ///
  /// batmon-ha (`bmslib/bt.py`) also scans without service filter and
  /// matches devices by name prefix.
  Future<void> startScan() async {
    await UniversalBle.startScan();
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
  /// 1. BLE connect (10s timeout)
  /// 2. Discover services (10s timeout)
  /// 3. Find FFE0/FFE1
  /// 4. Subscribe to notifications
  Future<void> connect(String deviceId) async {
    _connectedDeviceId = deviceId;

    // Listen for connection state changes
    _connectionSub?.cancel();
    _connectionSub = UniversalBle.connectionStream(deviceId).listen(
      (isConnected) {
        debugPrint('[JK-BMS] Connection state: $isConnected');
        if (!isConnected) {
          _log('RX', 'Disconnected from $deviceId');
          _connectedDeviceId = null;
        }
      },
    );

    // Connect with timeout
    _log('TX', 'Connecting to $deviceId...');
    debugPrint('[JK-BMS] Connecting to $deviceId...');
    try {
      await UniversalBle.connect(deviceId)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[JK-BMS] Connect timeout after 10s');
      _connectedDeviceId = null;
      throw Exception('Bağlantı zaman aşımına uğradı (10s)');
    }
    _log('RX', 'Connected to $deviceId');
    debugPrint('[JK-BMS] Connected to $deviceId');

    // Discover services with timeout
    _log('TX', 'Discovering services...');
    debugPrint('[JK-BMS] Discovering services...');
    late List<BleService> services;
    try {
      services = await UniversalBle.discoverServices(deviceId)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[JK-BMS] Service discovery timeout after 10s');
      throw Exception('Servis keşfi zaman aşımına uğradı (10s)');
    }
    _log('RX', 'Found ${services.length} services');
    debugPrint('[JK-BMS] Found ${services.length} services');

    // Log all discovered services for debugging
    for (final service in services) {
      debugPrint('[JK-BMS]   Service: ${service.uuid}');
      for (final char in service.characteristics) {
        debugPrint('[JK-BMS]     Char: ${char.uuid} props=${char.properties}');
      }
    }

    // Find JK-BMS service using pattern matching
    final match = _findJkService(services);

    if (match == null) {
      debugPrint('[JK-BMS] No matching JK-BMS service found! Available:');
      for (final s in services) {
        debugPrint('[JK-BMS]   ${s.uuid}');
      }
      _eventController.add(BmsErrorEvent(
        message: 'JK-BMS servisi bulunamadı ($deviceId)',
      ));
      throw Exception(
        'JK-BMS servisi bulunamadı. '
        '${services.length} servis keşfedildi. '
        'Desteklenen: FFE0/FFE1, FF00/FF01+FF02, FFF0/FFF1+FFF2',
      );
    }

    _log('RX', 'Found JK-BMS service');
    debugPrint(
      '[JK-BMS] Using service=${match.service}, '
      'notify=${match.notifyChar}, write=${match.writeChar}',
    );

    // Store discovered UUIDs for write operations
    _foundServiceUuid = match.service;
    _foundWriteCharUuid = match.writeChar;
    _foundNotifyCharUuid = match.notifyChar;

    // Subscribe to frame assembly
    _frameSub?.cancel();
    _frameSub = _frameAssembler.frameStream.listen(_onFrameAssembled);

    // Listen for characteristic value notifications
    _notifySub?.cancel();
    _notifySub = UniversalBle.characteristicValueStream(
      deviceId,
      match.notifyChar,
    ).listen((value) {
      _logHex('RX', value);
      _frameAssembler.addChunk(value);
    });

    // Enable notifications with timeout
    _log('TX', 'Enabling notifications on ${match.notifyChar}...');
    debugPrint('[JK-BMS] Enabling notifications on ${match.notifyChar}...');
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        match.service,
        match.notifyChar,
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[JK-BMS] Notification subscription timeout');
      throw Exception('Notification aboneliği zaman aşımına uğradı');
    }
    _log('RX', 'Notifications enabled');
    debugPrint('[JK-BMS] Notifications enabled — ready!');
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
    _foundServiceUuid = null;
    _foundWriteCharUuid = null;
    _foundNotifyCharUuid = null;
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
    if (_connectedDeviceId == null ||
        _foundServiceUuid == null ||
        _foundWriteCharUuid == null) {
      _eventController.add(BmsErrorEvent(
        message: 'No device connected',
      ));
      return;
    }

    _logHex('TX', frame);
    debugPrint('[JK-BMS] TX ${frame.length} bytes to $_foundWriteCharUuid');

    try {
      await UniversalBle.write(
        _connectedDeviceId!,
        _foundServiceUuid!,
        _foundWriteCharUuid!,
        frame,
        withoutResponse: true,
      );
    } catch (e) {
      debugPrint('[JK-BMS] Write failed: $e');
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
