import 'dart:typed_data';

import 'daly_constants.dart';

/// Builds a 13-byte Daly BMS request frame.
///
/// [command] — command byte (e.g. [kDalyCmdSoc]).
/// [useBle] — if true (default), use BLE address (0x80); otherwise USB (0x40).
///
/// ```dart
/// final frame = buildDalyRequest(kDalyCmdSoc);
/// // → A5 80 90 08 00 00 00 00 00 00 00 00 BD
/// ```
Uint8List buildDalyRequest(int command, {bool useBle = true}) {
  final frame = Uint8List(kDalyFrameSize);

  frame[0] = kDalyHeader;
  frame[1] = useBle ? kDalyHostAddressBle : kDalyHostAddressUsb;
  frame[2] = command & 0xFF;
  frame[3] = kDalyDataLength;

  // Data bytes [4..11] are zero (read request has no payload).
  // Already initialised by Uint8List.

  // Checksum: sum of bytes [0..11] & 0xFF
  int sum = 0;
  for (int i = 0; i < kDalyFrameSize - 1; i++) {
    sum += frame[i];
  }
  frame[12] = sum & 0xFF;

  return frame;
}

/// Pre-built request for SOC/voltage/current (command `0x90`).
Uint8List dalySocRequest() => buildDalyRequest(kDalyCmdSoc);

/// Pre-built request for min/max cell voltage (command `0x91`).
Uint8List dalyMinMaxVoltageRequest() =>
    buildDalyRequest(kDalyCmdMinMaxVoltage);

/// Pre-built request for min/max temperature (command `0x92`).
Uint8List dalyMinMaxTempRequest() => buildDalyRequest(kDalyCmdMinMaxTemp);

/// Pre-built request for MOS status (command `0x93`).
Uint8List dalyMosStatusRequest() => buildDalyRequest(kDalyCmdMosStatus);

/// Pre-built request for status info (command `0x94`).
Uint8List dalyStatusInfoRequest() => buildDalyRequest(kDalyCmdStatusInfo);

/// Pre-built request for individual cell voltages (command `0x95`).
Uint8List dalyCellVoltagesRequest() =>
    buildDalyRequest(kDalyCmdCellVoltages);

/// Pre-built request for cell temperatures (command `0x96`).
Uint8List dalyCellTempsRequest() => buildDalyRequest(kDalyCmdCellTemps);

/// Pre-built request for failure status (command `0x98`).
Uint8List dalyFailureRequest() => buildDalyRequest(kDalyCmdFailure);
