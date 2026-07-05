import 'dart:typed_data';

import 'checksum.dart';
import 'constants.dart';

/// Builds a 20-byte JK-BMS request frame.
///
/// [command] — register/command byte (e.g. [kCommandCellInfo]).
/// [value]  — 32-bit little-endian value field (default 0).
/// [length] — the length byte at offset 5 (default 0 for reads).
///
/// ```dart
/// final frame = buildJkRequest(kCommandCellInfo);
/// // → AA 55 90 EB 96 00 00 00 00 00 ... 10
/// ```
Uint8List buildJkRequest(int command, {int value = 0, int length = 0}) {
  final frame = Uint8List(kRequestFrameLength);

  // Header
  frame[0] = 0xAA;
  frame[1] = 0x55;
  frame[2] = 0x90;
  frame[3] = 0xEB;

  // Command / register
  frame[4] = command & 0xFF;

  // Length
  frame[5] = length & 0xFF;

  // Value (little-endian 32-bit)
  frame[6] = value & 0xFF;
  frame[7] = (value >> 8) & 0xFF;
  frame[8] = (value >> 16) & 0xFF;
  frame[9] = (value >> 24) & 0xFF;

  // Bytes 10..18 are zero (padding) — already initialised by Uint8List.

  // CRC over bytes 0..18
  frame[19] = jkChecksum(frame, 19);

  return frame;
}

/// Pre-built request for cell/status info (command `0x96`).
Uint8List cellInfoRequest() => buildJkRequest(kCommandCellInfo);

/// Pre-built request for device info (command `0x97`).
Uint8List deviceInfoRequest() => buildJkRequest(kCommandDeviceInfo);

/// Pre-built request for logbook (command `0xA1`).
Uint8List logbookRequest() => buildJkRequest(kCommandLogbook);
