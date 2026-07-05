import 'dart:typed_data';

/// Reads an unsigned 16-bit little-endian value from [data] at [offset].
int u16le(Uint8List data, int offset) {
  return data[offset] | (data[offset + 1] << 8);
}

/// Reads a signed 16-bit little-endian value from [data] at [offset].
int i16le(Uint8List data, int offset) {
  final v = u16le(data, offset);
  return (v & 0x8000) != 0 ? v - 0x10000 : v;
}

/// Reads an unsigned 32-bit little-endian value from [data] at [offset].
int u32le(Uint8List data, int offset) {
  return (data[offset] |
          (data[offset + 1] << 8) |
          (data[offset + 2] << 16) |
          (data[offset + 3] << 24)) &
      0xFFFFFFFF;
}

/// Reads a signed 32-bit little-endian value from [data] at [offset].
int i32le(Uint8List data, int offset) {
  final v = u32le(data, offset);
  return v > 0x7FFFFFFF ? v - 0x100000000 : v;
}
