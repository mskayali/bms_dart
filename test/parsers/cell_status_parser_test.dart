import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jk_bms/src/protocol/checksum.dart';
import 'package:jk_bms/src/protocol/constants.dart';
import 'package:jk_bms/src/parsers/cell_status_parser.dart';

void main() {
  /// Creates a synthetic JK02 cell/status frame for testing.
  ///
  /// Populates known fields with realistic values so parsers can be
  /// verified against expected output.
  Uint8List _buildTestFrame(JkProtocol protocol) {
    final frame = Uint8List(320); // oversized to be safe
    final cellOffset = protocol.cellOffset;
    final mainOffset = protocol.mainOffset;
    final cellCount = protocol.cellCount;

    // Response header
    frame[0] = 0x55;
    frame[1] = 0xAA;
    frame[2] = 0xEB;
    frame[3] = 0x90;
    frame[4] = kFrameTypeCellInfo;

    // Cell voltages — set cell 1 to 3.298V (3298 raw), cell 2 to 3.300V
    void writeU16(int offset, int value) {
      frame[offset] = value & 0xFF;
      frame[offset + 1] = (value >> 8) & 0xFF;
    }

    void writeU32(int offset, int value) {
      frame[offset] = value & 0xFF;
      frame[offset + 1] = (value >> 8) & 0xFF;
      frame[offset + 2] = (value >> 16) & 0xFF;
      frame[offset + 3] = (value >> 24) & 0xFF;
    }

    void writeI32(int offset, int value) {
      if (value < 0) value = value + 0x100000000;
      writeU32(offset, value);
    }

    void writeI16(int offset, int value) {
      if (value < 0) value = value + 0x10000;
      writeU16(offset, value);
    }

    // Cell voltages: 3.298V, 3.300V, 3.250V, 3.310V for first 4 cells
    final voltages = [3298, 3300, 3250, 3310];
    for (int i = 0; i < cellCount; i++) {
      final v = i < voltages.length ? voltages[i] : 3280;
      writeU16(6 + i * 2, v);
    }

    // Enabled cell bitmask (4 cells enabled for 24S testing)
    writeU32(54 + cellOffset, 0x0000000F);

    // Cell statistics
    writeU16(58 + cellOffset, 3290); // average: 3.290V
    writeU16(60 + cellOffset, 60); // delta: 0.060V
    frame[62 + cellOffset] = 4; // max cell number
    frame[63 + cellOffset] = 3; // min cell number

    // Cell resistances (4 mΩ each)
    for (int i = 0; i < cellCount; i++) {
      writeU16(64 + cellOffset + i * 2, 4);
    }

    // Total voltage: 51.234V
    writeU32(118 + mainOffset, 51234);

    // Current: -12.500A (discharge)
    writeI32(126 + mainOffset, -12500);

    // Temperature 1: 25.3°C (253 raw)
    writeI16(130 + mainOffset, 253);

    // Temperature 2: 24.1°C (241 raw)
    writeI16(132 + mainOffset, 241);

    // MOS temperature (24S only): 35.0°C
    if (protocol == JkProtocol.jk02_24s) {
      writeI16(134 + mainOffset, 350);
    }

    // Errors: no errors
    if (protocol == JkProtocol.jk02_32s) {
      writeU32(134 + mainOffset, 0);
    } else {
      writeU16(136 + mainOffset, 0);
    }

    // Balance current: 0.5A
    writeI16(138 + mainOffset, 500);

    // Balancer action: 1 (charge balancer)
    frame[140 + mainOffset] = 1;

    // SOC: 85%
    frame[141 + mainOffset] = 85;

    // Capacity remaining: 100.000 Ah
    writeU32(142 + mainOffset, 100000);

    // Full capacity: 120.000 Ah
    writeU32(146 + mainOffset, 120000);

    // Cycle count: 42
    writeU32(150 + mainOffset, 42);

    // Total cycle capacity: 5040.000 Ah
    writeU32(154 + mainOffset, 5040000);

    // SOH: 98%
    frame[158 + mainOffset] = 98;

    // Total runtime: 86400 seconds (1 day)
    writeU32(162 + mainOffset, 86400);

    // Charging enabled
    frame[166 + mainOffset] = 1;

    // Discharging enabled
    frame[167 + mainOffset] = 1;

    // Precharge disabled
    frame[168 + mainOffset] = 0;

    // Balancer working
    frame[169 + mainOffset] = 1;

    // Heating disabled
    frame[183 + mainOffset] = 0;

    // CRC
    frame[299] = jkChecksum(frame, 299);

    return frame;
  }

  group('parseCellStatus — JK02_24S', () {
    late JkProtocol protocol;
    late Uint8List frame;

    setUp(() {
      protocol = JkProtocol.jk02_24s;
      frame = _buildTestFrame(protocol);
    });

    test('parses cell voltages correctly', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.cellVoltages.length, 24);
      expect(status.cellVoltages[0], closeTo(3.298, 0.001));
      expect(status.cellVoltages[1], closeTo(3.300, 0.001));
      expect(status.cellVoltages[2], closeTo(3.250, 0.001));
      expect(status.cellVoltages[3], closeTo(3.310, 0.001));
    });

    test('parses enabled cell count from bitmask', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.enabledCellCount, 4);
    });

    test('parses cell statistics', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.averageCellVoltage, closeTo(3.290, 0.001));
      expect(status.deltaCellVoltage, closeTo(0.060, 0.001));
      expect(status.maxVoltageCellNumber, 4);
      expect(status.minVoltageCellNumber, 3);
    });

    test('parses total voltage', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.totalVoltage, closeTo(51.234, 0.001));
    });

    test('parses current as signed (negative = discharge)', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.current, closeTo(-12.500, 0.001));
    });

    test('computes power from voltage × current', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.power, closeTo(51.234 * -12.500, 0.1));
    });

    test('parses temperatures', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.temperature1, closeTo(25.3, 0.1));
      expect(status.temperature2, closeTo(24.1, 0.1));
      expect(status.mosTemperature, closeTo(35.0, 0.1));
    });

    test('parses SOC and SOH', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.soc, 85);
      expect(status.soh, 98);
    });

    test('parses capacity values', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.capacityRemaining, closeTo(100.0, 0.001));
      expect(status.fullCapacity, closeTo(120.0, 0.001));
    });

    test('parses cycle count', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.cycleCount, 42);
    });

    test('parses MOSFET states', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.chargingEnabled, true);
      expect(status.dischargingEnabled, true);
      expect(status.prechargeEnabled, false);
      expect(status.balancerWorking, true);
      expect(status.heatingEnabled, false);
    });

    test('parses balancer info', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.balanceCurrent, closeTo(0.5, 0.001));
      expect(status.balancerAction, 1);
    });

    test('totalRuntimeFormatted works correctly', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.totalRuntimeFormatted, '1d 0h 0m');
    });

    test('hasErrors returns false when no errors', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.hasErrors, false);
    });
  });

  group('parseCellStatus — JK02_32S', () {
    late JkProtocol protocol;
    late Uint8List frame;

    setUp(() {
      protocol = JkProtocol.jk02_32s;
      frame = _buildTestFrame(protocol);
    });

    test('parses 32 cell voltages', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.cellVoltages.length, 32);
    });

    test('applies correct offsets for 32S variant', () {
      final status = parseCellStatus(frame, protocol);
      expect(status.totalVoltage, closeTo(51.234, 0.001));
      expect(status.current, closeTo(-12.500, 0.001));
      expect(status.soc, 85);
    });
  });
}
