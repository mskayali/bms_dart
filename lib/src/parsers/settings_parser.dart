import 'dart:typed_data';

import '../models/jk_settings.dart';
import '../protocol/byte_reader.dart';
import '../protocol/constants.dart';

/// Parses a JK-BMS settings frame (frame type `0x01`).
///
/// The settings frame contains the BMS configuration parameters.
/// batmon-ha uses this frame to read `num_cells` (byte 114) and
/// the nominal capacity (bytes 146–149), which are critical for
/// accurate SOC calculation.
///
/// Settings frame field offsets are derived from:
/// - batmon-ha `bmslib/models/jikong.py` (`_decode_msg`, `_decode_sample`)
/// - ESPHome JK-BMS BLE component
///
/// ```dart
/// final settings = parseSettings(frameData, JkProtocol.jk02_32s);
/// print('Cells: ${settings.numCells}');
/// print('Capacity: ${settings.nominalCapacity} Ah');
/// ```
JkSettings parseSettings(Uint8List data, JkProtocol protocol) {
  final mainOffset = protocol.mainOffset;

  // --- Cell count (byte 114) ---
  // batmon-ha: `bms.num_cells = settings_buf[114]`
  final numCells = data[114];

  // --- Protection thresholds ---
  // These offsets come from the ESPHome JK-BMS component's settings decode.
  // All voltage values are u32le × 0.001V, all current values are u32le × 0.001A.

  // Cell OVP (over-voltage protection): bytes 8–11
  final cellOvp = u32le(data, 8) * kVoltageScale;

  // Cell OVP recovery: bytes 12–15
  final cellOvpRecovery = u32le(data, 12) * kVoltageScale;

  // Cell UVP (under-voltage protection): bytes 16–19
  final cellUvp = u32le(data, 16) * kVoltageScale;

  // Cell UVP recovery: bytes 20–23
  final cellUvpRecovery = u32le(data, 20) * kVoltageScale;

  // Balance start voltage: bytes 24–27
  final balanceStartVoltage = u32le(data, 24) * kVoltageScale;

  // Balance trigger delta: bytes 28–31
  final balanceDelta = u32le(data, 28) * kVoltageScale;

  // Max charge current: bytes 40–43
  final maxChargeCurrent = u32le(data, 40) * kCurrentScale;

  // Max discharge current: bytes 48–51
  final maxDischargeCurrent = u32le(data, 48) * kCurrentScale;

  // Temperature protections (i16le × 0.1°C)
  // Charge OTP: bytes 56–57
  final chargeOtp = i16le(data, 56) * kTemperatureScale;

  // Charge UTP: bytes 62–63
  final chargeUtp = i16le(data, 62) * kTemperatureScale;

  // Discharge OTP: bytes 68–69
  final dischargeOtp = i16le(data, 68) * kTemperatureScale;

  // Discharge UTP: bytes 74–75
  final dischargeUtp = i16le(data, 74) * kTemperatureScale;

  // Nominal capacity: bytes 146–149 + mainOffset (u32le × 0.001 Ah)
  // batmon-ha: `aged_capacity = struct.unpack_from('<I', buf, 146+ofs)[0] * 0.001`
  final nominalCapacity = u32le(data, 146 + mainOffset) * kCapacityScale;

  // Battery type: byte 243 + mainOffset
  // 0: LFP, 1: Li-ion, 2: LTO
  int batteryType = 0;
  final btIdx = 243 + mainOffset;
  if (btIdx < data.length) {
    batteryType = data[btIdx];
  }

  return JkSettings(
    numCells: numCells,
    nominalCapacity: nominalCapacity,
    cellOvp: cellOvp,
    cellOvpRecovery: cellOvpRecovery,
    cellUvp: cellUvp,
    cellUvpRecovery: cellUvpRecovery,
    balanceStartVoltage: balanceStartVoltage,
    balanceDelta: balanceDelta,
    maxChargeCurrent: maxChargeCurrent,
    maxDischargeCurrent: maxDischargeCurrent,
    chargeOtp: chargeOtp,
    chargeUtp: chargeUtp,
    dischargeOtp: dischargeOtp,
    dischargeUtp: dischargeUtp,
    batteryType: batteryType,
    rawData: data.toList(),
  );
}
