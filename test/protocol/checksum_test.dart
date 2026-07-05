import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jk_bms/src/protocol/checksum.dart';

void main() {
  group('jkChecksum', () {
    test('returns 0 for empty data', () {
      expect(jkChecksum(Uint8List(0)), 0);
    });

    test('returns 0 for all-zero data', () {
      expect(jkChecksum(Uint8List(20)), 0);
    });

    test('computes correct CRC for device info request', () {
      // AA + 55 + 90 + EB + 97 = 0x311 → 0x11
      final data = Uint8List(19);
      data[0] = 0xAA;
      data[1] = 0x55;
      data[2] = 0x90;
      data[3] = 0xEB;
      data[4] = 0x97;
      expect(jkChecksum(data, 19), 0x11);
    });

    test('computes correct CRC for cell info request', () {
      // AA + 55 + 90 + EB + 96 = 0x310 → 0x10
      final data = Uint8List(19);
      data[0] = 0xAA;
      data[1] = 0x55;
      data[2] = 0x90;
      data[3] = 0xEB;
      data[4] = 0x96;
      expect(jkChecksum(data, 19), 0x10);
    });

    test('computes correct CRC for logbook request', () {
      // AA + 55 + 90 + EB + A1 = 0x31B → 0x1B
      final data = Uint8List(19);
      data[0] = 0xAA;
      data[1] = 0x55;
      data[2] = 0x90;
      data[3] = 0xEB;
      data[4] = 0xA1;
      expect(jkChecksum(data, 19), 0x1B);
    });

    test('wraps around on overflow', () {
      final data = Uint8List.fromList([0xFF, 0x01]);
      expect(jkChecksum(data), 0x00); // 0x100 & 0xFF = 0
    });

    test('respects length parameter', () {
      final data = Uint8List.fromList([0x10, 0x20, 0x30]);
      expect(jkChecksum(data, 2), 0x30); // only first 2 bytes
    });
  });

  group('validateResponseCrc', () {
    test('returns false for frame shorter than 300 bytes', () {
      expect(validateResponseCrc(Uint8List(299)), false);
    });

    test('returns true for valid CRC', () {
      final frame = Uint8List(300);
      // Fill with known values
      for (int i = 0; i < 299; i++) {
        frame[i] = i & 0xFF;
      }
      // Set CRC at index 299
      frame[299] = jkChecksum(frame, 299);
      expect(validateResponseCrc(frame), true);
    });

    test('returns false for invalid CRC', () {
      final frame = Uint8List(300);
      for (int i = 0; i < 299; i++) {
        frame[i] = i & 0xFF;
      }
      frame[299] = 0x00; // wrong CRC
      expect(validateResponseCrc(frame), false);
    });
  });
}
