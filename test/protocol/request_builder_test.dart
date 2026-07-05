import 'package:flutter_test/flutter_test.dart';

import 'package:jk_bms/src/protocol/checksum.dart';
import 'package:jk_bms/src/protocol/constants.dart';
import 'package:jk_bms/src/protocol/request_builder.dart';

void main() {
  group('buildJkRequest', () {
    test('produces exactly 20 bytes', () {
      final frame = buildJkRequest(kCommandCellInfo);
      expect(frame.length, kRequestFrameLength);
    });

    test('has correct header bytes', () {
      final frame = buildJkRequest(kCommandCellInfo);
      expect(frame[0], 0xAA);
      expect(frame[1], 0x55);
      expect(frame[2], 0x90);
      expect(frame[3], 0xEB);
    });

    test('device info request matches protocol spec', () {
      // Expected: AA 55 90 EB 97 00 00 00 00 00 00 00 00 00 00 00 00 00 00 11
      final frame = buildJkRequest(kCommandDeviceInfo);
      expect(frame[4], 0x97);
      expect(frame[5], 0x00);
      expect(frame[19], 0x11);
    });

    test('cell info request matches protocol spec', () {
      // Expected: AA 55 90 EB 96 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10
      final frame = buildJkRequest(kCommandCellInfo);
      expect(frame[4], 0x96);
      expect(frame[19], 0x10);
    });

    test('logbook request matches protocol spec', () {
      // Expected: AA 55 90 EB A1 00 00 00 00 00 00 00 00 00 00 00 00 00 00 1B
      final frame = buildJkRequest(kCommandLogbook);
      expect(frame[4], 0xA1);
      expect(frame[19], 0x1B);
    });

    test('CRC is valid for all requests', () {
      final frame = buildJkRequest(0x42, value: 0x12345678, length: 0x04);
      final crc = jkChecksum(frame, 19);
      expect(frame[19], crc);
    });

    test('value is encoded as little-endian', () {
      final frame = buildJkRequest(kCommandCellInfo, value: 0xAABBCCDD);
      expect(frame[6], 0xDD); // LSB
      expect(frame[7], 0xCC);
      expect(frame[8], 0xBB);
      expect(frame[9], 0xAA); // MSB
    });

    test('padding bytes are zero', () {
      final frame = buildJkRequest(kCommandCellInfo);
      for (int i = 10; i < 19; i++) {
        expect(frame[i], 0, reason: 'Byte $i should be 0');
      }
    });
  });

  group('convenience builders', () {
    test('cellInfoRequest equals manual build', () {
      final a = cellInfoRequest();
      final b = buildJkRequest(kCommandCellInfo);
      expect(a, equals(b));
    });

    test('deviceInfoRequest equals manual build', () {
      final a = deviceInfoRequest();
      final b = buildJkRequest(kCommandDeviceInfo);
      expect(a, equals(b));
    });

    test('logbookRequest equals manual build', () {
      final a = logbookRequest();
      final b = buildJkRequest(kCommandLogbook);
      expect(a, equals(b));
    });
  });
}
