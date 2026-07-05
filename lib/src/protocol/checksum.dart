import 'dart:typed_data';

/// 8-bit additive checksum used by JK-BMS protocol.
///
/// This is **not** a polynomial CRC. It is the simple sum of all bytes
/// modulo 256.
///
/// ```dart
/// final crc = jkChecksum(data, 19); // CRC of first 19 bytes
/// ```
int jkChecksum(Uint8List data, [int? length]) {
  final len = length ?? data.length;
  int crc = 0;
  for (int i = 0; i < len; i++) {
    crc = (crc + data[i]) & 0xFF;
  }
  return crc;
}

/// Validates the CRC of a response frame.
///
/// Computes `sum(frame[0..298]) & 0xFF` and compares with `frame[299]`.
/// Returns `true` if the CRC matches.
bool validateResponseCrc(Uint8List frame) {
  if (frame.length < 300) return false;
  final expected = frame[299];
  final actual = jkChecksum(frame, 299);
  return actual == expected;
}
