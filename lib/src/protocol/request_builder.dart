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

// ---------------------------------------------------------------------------
// NW TLV Protocol (0x4E 0x57) — used by newer JK-BMS models like WE24300
// ---------------------------------------------------------------------------

/// Build a NW TLV "Read All Data" request frame.
///
/// Frame format:
/// ```
/// 4E 57 00 13 00 00 00 00 06 03 00 00 00 00 00 00 68 00 00 01 29
/// │  │  │     │           │  │                    │  │        │
/// │  │  │     │           │  └ FrameSource: BLE   │  │        └ CRC (sum of bytes)
/// │  │  │     │           └ Command: 0x06 ReadAll │  └ Record number
/// │  │  │     └ Terminal Number (4 bytes)          └ End: 0x68
/// │  │  └ Length: 0x0013 (19 bytes)
/// └──┴ Start: "NW" (0x4E 0x57)
/// ```
Uint8List buildNwReadAllRequest() {
  final frame = Uint8List.fromList([
    0x4E, 0x57, // Start frame "NW"
    0x00, 0x13, // Length = 19
    0x00, 0x00, 0x00, 0x00, // Terminal number
    0x06, // Command: Read All
    0x03, // Frame source: BLE (0x03)
    0x00, // Transport type: Request
    0x00, 0x00, 0x00, 0x00, 0x00, // Data (Read All = no specific ID)
    0x68, // End identifier
    0x00, 0x00, 0x01, 0x29, // CRC placeholder
  ]);

  // Calculate CRC: sum of all bytes from offset 0 to length-4
  int sum = 0;
  for (int i = 0; i < frame.length - 4; i++) {
    sum += frame[i];
  }
  frame[frame.length - 4] = (sum >> 24) & 0xFF;
  frame[frame.length - 3] = (sum >> 16) & 0xFF;
  frame[frame.length - 2] = (sum >> 8) & 0xFF;
  frame[frame.length - 1] = sum & 0xFF;

  return frame;
}
