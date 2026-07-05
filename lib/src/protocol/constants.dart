import 'dart:typed_data';

/// JK-BMS GATT protocol constants.
///
/// All UUIDs, headers, command codes, and frame layout values
/// derived from the JK-BMS BLE protocol specification.

// ---------------------------------------------------------------------------
// GATT Service / Characteristic
// ---------------------------------------------------------------------------

/// Primary JK-BMS BLE service UUID.
const String kJkServiceUuid = '0000FFE0-0000-1000-8000-00805F9B34FB';

/// Primary JK-BMS BLE characteristic UUID (write + notify).
const String kJkCharacteristicUuid = '0000FFE1-0000-1000-8000-00805F9B34FB';

// ---------------------------------------------------------------------------
// Frame Headers
// ---------------------------------------------------------------------------

/// Client → BMS request preamble bytes.
final Uint8List kRequestHeader = Uint8List.fromList([0xAA, 0x55, 0x90, 0xEB]);

/// BMS → Client response preamble bytes.
final Uint8List kResponseHeader =
    Uint8List.fromList([0x55, 0xAA, 0xEB, 0x90]);

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Request cell voltages, temperatures, SOC, current, etc.
const int kCommandCellInfo = 0x96;

/// Request device info (model, firmware, serial, etc.).
const int kCommandDeviceInfo = 0x97;

/// Request logbook entries.
const int kCommandLogbook = 0xA1;

// ---------------------------------------------------------------------------
// Frame Layout
// ---------------------------------------------------------------------------

/// Fixed request frame length in bytes.
const int kRequestFrameLength = 20;

/// Minimum response frame length before attempting decode.
const int kMinResponseSize = 300;

/// Maximum response buffer size (384 + 16).
const int kMaxResponseBuffer = 400;

/// Byte index of the response CRC.
const int kResponseCrcIndex = 299;

// ---------------------------------------------------------------------------
// Response Frame Types
// ---------------------------------------------------------------------------

/// Settings frame.
const int kFrameTypeSettings = 0x01;

/// Cell/status info frame.
const int kFrameTypeCellInfo = 0x02;

/// Device info frame.
const int kFrameTypeDeviceInfo = 0x03;

/// Logbook frame.
const int kFrameTypeLogbook = 0x05;

// ---------------------------------------------------------------------------
// Protocol Versions
// ---------------------------------------------------------------------------

/// Supported JK-BMS protocol families.
enum JkProtocol {
  /// JK04 family.
  jk04(code: 0x01, cellOffset: 0, mainOffset: 0, cellCount: 24),

  /// JK02 with up to 24 series cells.
  jk02_24s(code: 0x02, cellOffset: 0, mainOffset: 0, cellCount: 24),

  /// JK02 with up to 32 series cells.
  jk02_32s(code: 0x03, cellOffset: 16, mainOffset: 32, cellCount: 32);

  const JkProtocol({
    required this.code,
    required this.cellOffset,
    required this.mainOffset,
    required this.cellCount,
  });

  /// Protocol identification byte.
  final int code;

  /// Byte offset added to cell-related field positions.
  final int cellOffset;

  /// Byte offset added to main BMS field positions.
  final int mainOffset;

  /// Maximum number of series cells.
  final int cellCount;
}

// ---------------------------------------------------------------------------
// Scaling Factors
// ---------------------------------------------------------------------------

/// Voltage scale: raw × 0.001 V
const double kVoltageScale = 0.001;

/// Current scale: raw × 0.001 A
const double kCurrentScale = 0.001;

/// Temperature scale: raw × 0.1 °C
const double kTemperatureScale = 0.1;

/// Capacity scale: raw × 0.001 Ah
const double kCapacityScale = 0.001;

/// Resistance scale: raw × 0.001 Ω
const double kResistanceScale = 0.001;

/// Power scale: raw × 0.001 W
const double kPowerScale = 0.001;
