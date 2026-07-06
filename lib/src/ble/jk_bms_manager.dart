import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../models/bms_event.dart';
import '../parsers/cell_status_parser.dart';
import '../parsers/daly_parser.dart';
import '../parsers/device_info_parser.dart';
import '../parsers/settings_parser.dart';
import '../protocol/constants.dart';
import '../protocol/daly_constants.dart';
import '../protocol/daly_frame_assembler.dart';
import '../protocol/daly_request_builder.dart';
import '../protocol/frame_assembler.dart';
import '../protocol/request_builder.dart';

/// Detected BMS protocol type.
enum BmsProtocolType {
  /// Not yet detected.
  unknown,

  /// JK-BMS JK02/JK04 protocol (AA 55 90 EB).
  jk02,

  /// Daly BMS UART protocol (A5 40 xx 08).
  daly,
}

/// Manages BLE connectivity and data exchange with BMS devices.
///
/// Supports both **JK-BMS** (JK02/JK04) and **Daly BMS** protocols.
/// Protocol is auto-detected on connection by probing with Daly commands
/// first (since Daly responds immediately), then JK02.
///
/// ## Usage
/// ```dart
/// final manager = JkBmsManager();
///
/// manager.eventStream.listen((event) {
///   if (event is BmsCellStatusEvent) {
///     print('SOC: ${event.data.soc}%');
///   }
/// });
///
/// manager.scanStream.listen((device) async {
///   await manager.connect(device.deviceId);
///   await manager.requestCellStatus();
/// });
/// manager.startScan();
/// ```
class JkBmsManager {
  JkBmsManager({this.protocol = JkProtocol.jk02_32s});

  /// JK protocol version (used only when JK02 protocol is detected).
  final JkProtocol protocol;

  final _eventController = StreamController<BmsEvent>.broadcast();
  final _logController = StreamController<BmsLogEntry>.broadcast();

  // JK02 frame assembler
  final _jkFrameAssembler = FrameAssembler();

  // Daly frame assembler
  final _dalyFrameAssembler = DalyFrameAssembler();

  // Accumulated Daly data
  DalyBmsData _dalyData = DalyBmsData();

  StreamSubscription<AssembledFrame>? _jkFrameSub;
  StreamSubscription<DalyFrame>? _dalyFrameSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Uint8List>? _notifySub;
  String? _connectedDeviceId;
  String? _foundServiceUuid;
  String? _foundWriteCharUuid;
  String? _foundNotifyCharUuid;

  /// Detected protocol type for the current connection.
  BmsProtocolType _detectedProtocol = BmsProtocolType.unknown;

  /// Whether Daly device uses BLE address (0x80) or USB address (0x40).
  /// Determined during auto-detection probe.
  bool _dalyUseBleAddress = true;

  // ---------------------------------------------------------------------------
  // UUID variant matching
  // ---------------------------------------------------------------------------

  /// Known JK-BMS service/characteristic UUID patterns.
  static const _jkServicePatterns = [
    // Pattern: serviceContains, notifyContains, writeContains
    ('FFE0', 'FFE1', 'FFE1'), // Classic JK-BMS (same char for both)
    ('FF00', 'FF01', 'FF02'), // Standard newer models
    ('FFF0', 'FFF1', 'FFF2'), // FFF0 variant
  ];

  /// Attempt to find JK-BMS service/characteristic from discovered services.
  ({String service, String notifyChar, String writeChar})? _findJkService(
    List<BleService> services,
  ) {
    for (final (svcPattern, notifyPattern, writePattern)
        in _jkServicePatterns) {
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
                  props.contains(
                      CharacteristicProperty.writeWithoutResponse))) {
            writeUuid = char.uuid;
          }
        }

        if (notifyUuid != null && writeUuid != null) {
          debugPrint(
            '[BMS] Matched JK pattern $svcPattern: '
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

  /// Find Daly BMS FFF0/FFF1/FFF2 service from discovered services.
  ({String service, String notifyChar, String writeChar})? _findDalyService(
    List<BleService> services,
  ) {
    for (final service in services) {
      if (!service.uuid.toUpperCase().contains('FFF0')) continue;

      String? notifyUuid;
      String? writeUuid;

      for (final char in service.characteristics) {
        final u = char.uuid.toUpperCase();
        if (u.contains('FFF1') &&
            char.properties.contains(CharacteristicProperty.notify)) {
          notifyUuid = char.uuid;
        }
        if (u.contains('FFF2') &&
            (char.properties.contains(CharacteristicProperty.write) ||
                char.properties
                    .contains(CharacteristicProperty.writeWithoutResponse))) {
          writeUuid = char.uuid;
        }
      }

      if (notifyUuid != null && writeUuid != null) {
        debugPrint(
          '[BMS] Found Daly service: '
          'service=${service.uuid}, notify=$notifyUuid, write=$writeUuid',
        );
        return (
          service: service.uuid,
          notifyChar: notifyUuid,
          writeChar: writeUuid,
        );
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

  /// Stream of scan results.
  Stream<BleDevice> get scanStream => UniversalBle.scanStream;

  /// Currently connected device ID, or null if disconnected.
  String? get connectedDeviceId => _connectedDeviceId;

  /// Detected protocol type for the current connection.
  BmsProtocolType get detectedProtocol => _detectedProtocol;

  /// Notify characteristic UUID discovered during connection.
  String? get connectedNotifyCharUuid => _foundNotifyCharUuid;

  /// Write characteristic UUID discovered during connection.
  String? get connectedWriteCharUuid => _foundWriteCharUuid;

  // ---------------------------------------------------------------------------
  // Public API — Scanning
  // ---------------------------------------------------------------------------

  /// Known BMS device name prefixes for scan filtering.
  static const _bmsNamePrefixes = [
    'JK-',
    'JK_',
    'Daly',
    'DL-',
    'WE',
    'SP-',
    'SH-',
    'Smart BMS',
    'SmartBMS',
    'BMS',
  ];

  /// Check if a BLE device looks like a BMS based on its advertised name.
  ///
  /// Returns true if the device name starts with any known BMS prefix.
  /// Devices with no name are excluded.
  static bool isBmsDevice(BleDevice device) {
    final name = device.name;
    if (name == null || name.isEmpty) return false;
    final upper = name.toUpperCase();
    return _bmsNamePrefixes.any(
      (prefix) => upper.startsWith(prefix.toUpperCase()),
    );
  }

  /// Start BLE scan for all nearby devices.
  ///
  /// Use [isBmsDevice] to filter results on the stream side,
  /// since most BMS devices don't advertise FFF0 in their
  /// advertisement packets.
  Future<void> startScan() async {
    await UniversalBle.startScan();
  }

  /// Start BLE scan filtered by FFF0 service UUID.
  ///
  /// Not all BMS devices advertise this UUID in their advertisement,
  /// so [startScan] (unfiltered) may discover more devices.
  Future<void> startScanWithServiceFilter() async {
    await UniversalBle.startScan(
      scanFilter: ScanFilter(
        withServices: [kDalyServiceUuid],
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

  /// Connect to a BMS device by [deviceId].
  ///
  /// Performs full connection with auto protocol detection:
  /// 1. BLE connect
  /// 2. Discover services
  /// 3. Try Daly protocol first (FFF0/FFF1/FFF2)
  /// 4. Fall back to JK02 protocol
  Future<void> connect(String deviceId) async {
    _connectedDeviceId = deviceId;
    _detectedProtocol = BmsProtocolType.unknown;
    _dalyData = DalyBmsData();

    // Listen for connection state changes
    _connectionSub?.cancel();
    _connectionSub = UniversalBle.connectionStream(deviceId).listen(
      (isConnected) {
        debugPrint('[BMS] Connection state: $isConnected');
        if (!isConnected) {
          _log('RX', 'Disconnected from $deviceId');
          _connectedDeviceId = null;
        }
      },
    );

    // Connect with timeout
    _log('TX', 'Connecting to $deviceId...');
    debugPrint('[BMS] Connecting to $deviceId...');
    try {
      await UniversalBle.connect(deviceId)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[BMS] Connection timeout');
      throw Exception('Bağlantı zaman aşımına uğradı');
    }

    _log('RX', 'Connected to $deviceId');
    debugPrint('[BMS] Connected to $deviceId');

    // Discover services
    _log('TX', 'Discovering services...');
    debugPrint('[BMS] Discovering services...');

    late final List<BleService> services;
    try {
      services = await UniversalBle.discoverServices(deviceId)
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[BMS] Service discovery timeout');
      throw Exception('Servis keşfi zaman aşımına uğradı');
    }

    _log('RX', 'Found ${services.length} services');
    debugPrint('[BMS] Found ${services.length} services');

    // Log all services for debugging
    for (final service in services) {
      debugPrint('[BMS]   Service: ${service.uuid}');
      for (final char in service.characteristics) {
        debugPrint(
            '[BMS]     Char: ${char.uuid} props=${char.properties}');
      }
    }

    // --- Protocol Auto-Detection ---
    // Try Daly first (FFF0/FFF1/FFF2) since our device uses it
    final dalyMatch = _findDalyService(services);
    if (dalyMatch != null) {
      final success = await _tryDalyProtocol(deviceId, dalyMatch);
      if (success) {
        _detectedProtocol = BmsProtocolType.daly;
        debugPrint('[BMS] ✅ Daly protocol detected!');
        _log('RX', 'Protocol: Daly BMS');
        return;
      }
    }

    // Try JK02 protocol
    final jkMatch = _findJkService(services);
    if (jkMatch != null) {
      await _setupJkProtocol(deviceId, jkMatch, services);
      _detectedProtocol = BmsProtocolType.jk02;
      debugPrint('[BMS] ✅ JK02 protocol selected');
      _log('RX', 'Protocol: JK02');
      return;
    }

    // No matching service found
    debugPrint('[BMS] ❌ No supported BMS service found');
    _eventController.add(BmsErrorEvent(
      message: 'Desteklenen BMS servisi bulunamadı',
    ));
  }

  /// Try Daly protocol: subscribe to FFF1, send 0x90, wait for response.
  Future<bool> _tryDalyProtocol(
    String deviceId,
    ({String service, String notifyChar, String writeChar}) match,
  ) async {
    debugPrint('[BMS] Trying Daly protocol on ${match.service}...');

    // Subscribe to Daly frame assembler
    _dalyFrameSub?.cancel();
    _dalyFrameSub = _dalyFrameAssembler.frameStream.listen(_onDalyFrame);

    // Enable notifications on FFF1
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        match.service,
        match.notifyChar,
      ).timeout(const Duration(seconds: 5));
      debugPrint('[BMS] Daly FFF1 notifications enabled');
    } catch (e) {
      debugPrint('[BMS] Daly notification subscribe failed: $e');
      return false;
    }

    // Store UUIDs
    _foundServiceUuid = match.service;
    _foundWriteCharUuid = match.writeChar;
    _foundNotifyCharUuid = match.notifyChar;

    // Send Daly SOC probe — try BLE address (0x80) first, then USB (0x40)
    for (final useBle in [true, false]) {
      final addrStr = useBle ? '0x80 (BLE)' : '0x40 (USB)';
      debugPrint('[BMS] Sending Daly SOC probe with address $addrStr...');

      // Fresh completer for each attempt
      final probeCompleter = Completer<bool>();

      // Re-subscribe to capture response for this attempt
      _notifySub?.cancel();
      _notifySub = UniversalBle.characteristicValueStream(
        deviceId,
        match.notifyChar,
      ).listen((value) {
        debugPrint('[BMS] Daly RX: ${value.length} bytes');
        _logHex('RX', value);
        _dalyFrameAssembler.addChunk(value);
        if (!probeCompleter.isCompleted) {
          probeCompleter.complete(true);
        }
      });

      final probeFrame = buildDalyRequest(kDalyCmdSoc, useBle: useBle);
      try {
        await UniversalBle.write(
          deviceId,
          match.service,
          match.writeChar,
          probeFrame,
          withoutResponse: false,
        );
        debugPrint('[BMS] Daly probe $addrStr sent OK');
      } catch (e) {
        debugPrint('[BMS] Daly probe $addrStr write failed: $e');
        try {
          await UniversalBle.write(
            deviceId,
            match.service,
            match.writeChar,
            probeFrame,
            withoutResponse: true,
          );
        } catch (e2) {
          debugPrint('[BMS] Daly probe $addrStr also failed: $e2');
          continue;
        }
      }

      // Wait up to 2 seconds for a response
      try {
        final gotResponse = await probeCompleter.future
            .timeout(const Duration(seconds: 2));
        if (gotResponse) {
          _dalyUseBleAddress = useBle;
          debugPrint('[BMS] Daly responded to $addrStr ✅');
          return true;
        }
      } on TimeoutException {
        debugPrint('[BMS] Daly probe $addrStr: no response');
        continue;
      }
    }

    // Neither address worked
    _notifySub?.cancel();
    return false;
  }
  /// Set up JK02 protocol (legacy path).
  Future<void> _setupJkProtocol(
    String deviceId,
    ({String service, String notifyChar, String writeChar}) match,
    List<BleService> services,
  ) async {
    debugPrint(
      '[BMS] Using JK service=${match.service}, '
      'notify=${match.notifyChar}, write=${match.writeChar}',
    );

    _foundServiceUuid = match.service;
    _foundWriteCharUuid = match.writeChar;
    _foundNotifyCharUuid = match.notifyChar;

    // Subscribe to JK frame assembly
    _jkFrameSub?.cancel();
    _jkFrameSub = _jkFrameAssembler.frameStream.listen(_onJkFrameAssembled);

    // Listen for characteristic value notifications
    _notifySub?.cancel();
    _notifySub = UniversalBle.characteristicValueStream(
      deviceId,
      match.notifyChar,
    ).listen((value) {
      _logHex('RX', value);
      _jkFrameAssembler.addChunk(value);
    });

    // Enable notifications
    _log('TX', 'Enabling notifications on ${match.notifyChar}...');
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        match.service,
        match.notifyChar,
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw Exception('Notification aboneliği zaman aşımına uğradı');
    }
    _log('RX', 'Notifications enabled');
  }

  /// Disconnect from the currently connected device.
  Future<void> disconnect() async {
    if (_connectedDeviceId != null) {
      try {
        await UniversalBle.disconnect(_connectedDeviceId!);
      } catch (_) {}
    }
    _connectedDeviceId = null;
    _detectedProtocol = BmsProtocolType.unknown;
    _notifySub?.cancel();
    _notifySub = null;
    _jkFrameAssembler.reset();
    _dalyFrameAssembler.reset();
    _foundServiceUuid = null;
    _foundWriteCharUuid = null;
    _foundNotifyCharUuid = null;
  }

  // ---------------------------------------------------------------------------
  // Public API — Commands
  // ---------------------------------------------------------------------------

  /// Request cell/status data.
  ///
  /// - **Daly**: Sends 0x93 (MOS), 0x92 (temps), 0x91 (min/max V),
  ///            0x95 (cell voltages), 0x96 (cell temps), 0x90 (SOC — last,
  ///            triggers final consolidated event)
  /// - **JK02**: Sends command 0x96
  Future<void> requestCellStatus() async {
    if (_detectedProtocol == BmsProtocolType.daly) {
      final ble = _dalyUseBleAddress;
      // Send MOS status FIRST so MOSFET states and capacity are
      // accumulated before the final event emission.
      await _writeDalyCommand(buildDalyRequest(kDalyCmdMosStatus, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Status info includes cycle count (bytes 6-7)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdStatusInfo, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      await _writeDalyCommand(buildDalyRequest(kDalyCmdMinMaxTemp, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      await _writeDalyCommand(buildDalyRequest(kDalyCmdMinMaxVoltage, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      await _writeDalyCommand(buildDalyRequest(kDalyCmdCellVoltages, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      await _writeDalyCommand(buildDalyRequest(kDalyCmdCellTemps, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      await _writeDalyCommand(buildDalyRequest(kDalyCmdFailure, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // SOC last — this triggers the primary cell status event with all
      // accumulated data from the previous commands.
      await _writeDalyCommand(buildDalyRequest(kDalyCmdSoc, useBle: ble));
    } else {
      await _writeFrame(cellInfoRequest());
    }
  }

  /// Request device info.
  ///
  /// - **Daly**: Sends 0x94 (status info with cell count)
  /// - **JK02**: Sends command 0x97
  Future<void> requestDeviceInfo() async {
    if (_detectedProtocol == BmsProtocolType.daly) {
      final ble = _dalyUseBleAddress;
      // Standard status info (cell count, NTC count)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdStatusInfo, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Extended: Rated parameters (nominal voltage, capacity)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdRatedParams, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Extended: Battery details (production date, etc.)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdBatteryDetails, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Extended: Battery code / serial number (ASCII)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdBatteryCode, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Extended: Software Version (ASCII)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdSoftwareVersion, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Extended: Hardware Version (ASCII)
      await _writeDalyCommand(buildDalyRequest(kDalyCmdHardwareVersion, useBle: ble));
      await Future.delayed(const Duration(milliseconds: 200));
      // Extended: Unknown 0x54
      await _writeDalyCommand(buildDalyRequest(kDalyCmdUnknown54, useBle: ble));
    } else {
      await _writeFrame(deviceInfoRequest());
    }
  }

  /// Request logbook data (JK02 only).
  Future<void> requestLogbook() async {
    if (_detectedProtocol != BmsProtocolType.daly) {
      await _writeFrame(logbookRequest());
    }
  }

  /// Request settings data (JK02 only).
  Future<void> requestSettings() async {
    if (_detectedProtocol != BmsProtocolType.daly) {
      final frame = buildJkRequest(kFrameTypeSettings);
      await _writeFrame(frame);
    }
  }

  /// Send a custom request frame (JK02 only).
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
    _jkFrameSub?.cancel();
    _dalyFrameSub?.cancel();
    _connectionSub?.cancel();
    _notifySub?.cancel();
    _jkFrameAssembler.dispose();
    _dalyFrameAssembler.dispose();
    _eventController.close();
    _logController.close();
  }

  // ---------------------------------------------------------------------------
  // Internal — Write
  // ---------------------------------------------------------------------------

  /// Write a Daly command frame.
  Future<void> _writeDalyCommand(Uint8List frame) async {
    if (_connectedDeviceId == null ||
        _foundServiceUuid == null ||
        _foundWriteCharUuid == null) {
      return;
    }

    _logHex('TX', frame);
    debugPrint('[BMS] TX ${frame.length} bytes to $_foundWriteCharUuid');

    try {
      await UniversalBle.write(
        _connectedDeviceId!,
        _foundServiceUuid!,
        _foundWriteCharUuid!,
        frame,
        withoutResponse: false,
      );
    } catch (e) {
      try {
        await UniversalBle.write(
          _connectedDeviceId!,
          _foundServiceUuid!,
          _foundWriteCharUuid!,
          frame,
          withoutResponse: true,
        );
      } catch (e2) {
        debugPrint('[BMS] Daly write failed: $e2');
      }
    }
  }

  /// Write a JK02 request frame.
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
    debugPrint('[BMS] TX ${frame.length} bytes to $_foundWriteCharUuid');

    try {
      await UniversalBle.write(
        _connectedDeviceId!,
        _foundServiceUuid!,
        _foundWriteCharUuid!,
        frame,
        withoutResponse: false,
      );
    } catch (e) {
      debugPrint('[BMS] Write with response failed, trying without: $e');
      try {
        await UniversalBle.write(
          _connectedDeviceId!,
          _foundServiceUuid!,
          _foundWriteCharUuid!,
          frame,
          withoutResponse: true,
        );
      } catch (e2) {
        debugPrint('[BMS] Write also failed: $e2');
        _eventController.add(BmsErrorEvent(
          message: 'Write failed: $e2',
          details: e2,
        ));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — Daly Frame Handler
  // ---------------------------------------------------------------------------

  /// Handle a fully assembled Daly frame.
  ///
  /// Daly data accumulates across multiple command responses (0x90–0x98).
  /// We emit a [BmsCellStatusEvent] after every status-related command
  /// so the UI always reflects the latest accumulated data.
  /// The command order in [requestCellStatus] ensures that MOS status
  /// (0x93) is received before SOC (0x90), so the final emission
  /// contains MOSFET states, cycle count, and capacity.
  void _onDalyFrame(DalyFrame frame) {
    final cmdHex = '0x${frame.command.toRadixString(16).padLeft(2, '0')}';

    if (!frame.checksumValid) {
      debugPrint('[BMS] Daly frame checksum invalid for cmd $cmdHex');
      _eventController.add(BmsErrorEvent(
        message: 'Daly checksum hatası: $cmdHex',
      ));
      return;
    }

    _log(
      'RX',
      'Daly cmd=$cmdHex data=[${frame.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]',
    );

    // Parse into accumulated data
    parseDalyFrame(frame, _dalyData);

    // Emit device info after status/info responses
    if (frame.command == kDalyCmdStatusInfo ||
        frame.command == kDalyCmdRatedParams ||
        frame.command == kDalyCmdBatteryDetails ||
        frame.command == kDalyCmdBatteryCode ||
        frame.command == kDalyCmdSoftwareVersion ||
        frame.command == kDalyCmdHardwareVersion ||
        frame.command == kDalyCmdUnknown54) {
      _eventController.add(BmsDeviceInfoEvent(
        data: _dalyData.toDeviceInfo(),
      ));
    }

    // Emit cell status after any status-related command.
    // Since DalyBmsData accumulates, each emission includes all
    // previously parsed data. The SOC command (0x90) is sent last
    // in the request sequence, so its emission is the most complete.
    if (frame.command == kDalyCmdSoc ||
        frame.command == kDalyCmdMosStatus ||
        frame.command == kDalyCmdCellVoltages ||
        frame.command == kDalyCmdMinMaxTemp ||
        frame.command == kDalyCmdMinMaxVoltage) {
      _eventController.add(BmsCellStatusEvent(
        data: _dalyData.toCellStatus(),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Internal — JK02 Frame Handler
  // ---------------------------------------------------------------------------

  /// Handle a fully assembled JK02 frame.
  void _onJkFrameAssembled(AssembledFrame frame) {
    if (!frame.crcValid) {
      _eventController.add(BmsErrorEvent(
        message:
            'CRC mismatch for frame type 0x${frame.frameType.toRadixString(16)}',
      ));
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

  // ---------------------------------------------------------------------------
  // Internal — Logging
  // ---------------------------------------------------------------------------

  void _log(String direction, String message) {
    debugPrint('[BMS][$direction] $message');
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
