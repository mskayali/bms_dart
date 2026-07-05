import 'dart:typed_data';

import '../models/device_info.dart';

/// Parses a JK-BMS device info frame (frame type `0x03`).
///
/// The device info frame contains string fields for identification
/// data. Fields are read as null-terminated ASCII strings from known
/// offset regions.
///
/// Note: Exact offsets may vary by firmware version. This parser
/// attempts to read commonly observed fields.
JkDeviceInfo parseDeviceInfo(Uint8List data) {
  // Device info is stored as ASCII strings in fixed-width regions.
  // Common layout (may vary by firmware):
  //   Offset 6..21    : Vendor ID (16 bytes)
  //   Offset 22..29   : Hardware version (8 bytes)
  //   Offset 30..37   : Software version (8 bytes)
  //   Offset 38..53   : Device name (16 bytes)
  //   Offset 54..69   : Device passcode (16 bytes)
  //   Offset 70..77   : Manufacturing date (8 bytes)
  //   Offset 78..93   : Serial number (16 bytes)
  //   Offset 94..109  : Passcode (16 bytes)
  //   Offset 110..125 : Userdata (16 bytes)
  //   Offset 126..141 : Setup passcode (16 bytes)

  return JkDeviceInfo(
    rawData: data.toList(),
    vendorId: _readString(data, 6, 16),
    hardwareVersion: _readString(data, 22, 8),
    softwareVersion: _readString(data, 30, 8),
    deviceName: _readString(data, 38, 16),
    devicePasscode: _readString(data, 54, 16),
    manufacturingDate: _readString(data, 70, 8),
    serialNumber: _readString(data, 78, 16),
    passcode: _readString(data, 94, 16),
    userdata: _readString(data, 110, 16),
    setupPasscode: _readString(data, 126, 16),
  );
}

/// Reads a null-terminated ASCII string from [data] starting at [offset]
/// with a maximum [length].
String? _readString(Uint8List data, int offset, int length) {
  if (offset + length > data.length) return null;

  final bytes = <int>[];
  for (int i = 0; i < length; i++) {
    final b = data[offset + i];
    if (b == 0) break; // null terminator
    if (b >= 0x20 && b <= 0x7E) {
      bytes.add(b);
    }
  }

  if (bytes.isEmpty) return null;
  return String.fromCharCodes(bytes);
}
