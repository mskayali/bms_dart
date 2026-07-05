import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jk_bms/src/protocol/checksum.dart';
import 'package:jk_bms/src/protocol/constants.dart';
import 'package:jk_bms/src/parsers/settings_parser.dart';

/// Test data helper — builds a 300-byte settings frame (type 0x01) with
/// specific values at known offsets.
Uint8List _buildSettingsFrame({
  int numCells = 16,
  int cellOvpMv = 3650, // 3.650V
  int cellOvpRecoveryMv = 3600, // 3.600V
  int cellUvpMv = 2500, // 2.500V
  int cellUvpRecoveryMv = 2600, // 2.600V
  int balanceStartMv = 3300, // 3.300V
  int balanceDeltaMv = 10, // 0.010V
  int maxChargeCurrentMa = 100000, // 100A
  int maxDischargeCurrentMa = 100000, // 100A
  int chargeOtpRaw = 450, // 45.0°C
  int chargeUtpRaw = -50, // -5.0°C
  int dischargeOtpRaw = 550, // 55.0°C
  int dischargeUtpRaw = -100, // -10.0°C
  int nominalCapacityMah = 280000, // 280Ah
  int batteryType = 0, // LFP
  int mainOffset = 0,
}) {
  final data = Uint8List(300);

  // Preamble
  data[0] = 0x55;
  data[1] = 0xAA;
  data[2] = 0xEB;
  data[3] = 0x90;

  // Frame type = 0x01 (settings)
  data[4] = 0x01;

  // Cell OVP at bytes 8-11 (u32le)
  _writeU32le(data, 8, cellOvpMv);
  // Cell OVP recovery at bytes 12-15
  _writeU32le(data, 12, cellOvpRecoveryMv);
  // Cell UVP at bytes 16-19
  _writeU32le(data, 16, cellUvpMv);
  // Cell UVP recovery at bytes 20-23
  _writeU32le(data, 20, cellUvpRecoveryMv);
  // Balance start voltage at bytes 24-27
  _writeU32le(data, 24, balanceStartMv);
  // Balance delta at bytes 28-31
  _writeU32le(data, 28, balanceDeltaMv);
  // Max charge current at bytes 40-43
  _writeU32le(data, 40, maxChargeCurrentMa);
  // Max discharge current at bytes 48-51
  _writeU32le(data, 48, maxDischargeCurrentMa);
  // Charge OTP at bytes 56-57 (i16le)
  _writeI16le(data, 56, chargeOtpRaw);
  // Charge UTP at bytes 62-63
  _writeI16le(data, 62, chargeUtpRaw);
  // Discharge OTP at bytes 68-69
  _writeI16le(data, 68, dischargeOtpRaw);
  // Discharge UTP at bytes 74-75
  _writeI16le(data, 74, dischargeUtpRaw);

  // Num cells at byte 114
  data[114] = numCells;

  // Nominal capacity at bytes 146-149 + mainOffset
  _writeU32le(data, 146 + mainOffset, nominalCapacityMah);

  // Battery type at byte 243 + mainOffset
  final btIdx = 243 + mainOffset;
  if (btIdx < 300) {
    data[btIdx] = batteryType;
  }

  // Compute CRC (byte 299 = sum of bytes 0..298)
  data[299] = jkChecksum(data, 299);

  return data;
}

void _writeU32le(Uint8List data, int offset, int value) {
  data[offset] = value & 0xFF;
  data[offset + 1] = (value >> 8) & 0xFF;
  data[offset + 2] = (value >> 16) & 0xFF;
  data[offset + 3] = (value >> 24) & 0xFF;
}

void _writeI16le(Uint8List data, int offset, int value) {
  final v = value < 0 ? value + 0x10000 : value;
  data[offset] = v & 0xFF;
  data[offset + 1] = (v >> 8) & 0xFF;
}

void main() {
  group('parseSettings — JK02_24S', () {
    test('parses numCells correctly', () {
      final data = _buildSettingsFrame(numCells: 16);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.numCells, 16);
    });

    test('parses numCells for 8-cell', () {
      final data = _buildSettingsFrame(numCells: 8);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.numCells, 8);
    });

    test('parses nominal capacity', () {
      final data = _buildSettingsFrame(nominalCapacityMah: 280000);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.nominalCapacity, closeTo(280.0, 0.001));
    });

    test('parses cell OVP and recovery', () {
      final data = _buildSettingsFrame(
        cellOvpMv: 3650,
        cellOvpRecoveryMv: 3600,
      );
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.cellOvp, closeTo(3.650, 0.001));
      expect(settings.cellOvpRecovery, closeTo(3.600, 0.001));
    });

    test('parses cell UVP and recovery', () {
      final data = _buildSettingsFrame(
        cellUvpMv: 2500,
        cellUvpRecoveryMv: 2600,
      );
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.cellUvp, closeTo(2.500, 0.001));
      expect(settings.cellUvpRecovery, closeTo(2.600, 0.001));
    });

    test('parses balance settings', () {
      final data = _buildSettingsFrame(
        balanceStartMv: 3300,
        balanceDeltaMv: 10,
      );
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.balanceStartVoltage, closeTo(3.300, 0.001));
      expect(settings.balanceDelta, closeTo(0.010, 0.001));
    });

    test('parses current limits', () {
      final data = _buildSettingsFrame(
        maxChargeCurrentMa: 100000,
        maxDischargeCurrentMa: 150000,
      );
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.maxChargeCurrent, closeTo(100.0, 0.001));
      expect(settings.maxDischargeCurrent, closeTo(150.0, 0.001));
    });

    test('parses temperature protections', () {
      final data = _buildSettingsFrame(
        chargeOtpRaw: 450,
        chargeUtpRaw: -50,
        dischargeOtpRaw: 550,
        dischargeUtpRaw: -100,
      );
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.chargeOtp, closeTo(45.0, 0.1));
      expect(settings.chargeUtp, closeTo(-5.0, 0.1));
      expect(settings.dischargeOtp, closeTo(55.0, 0.1));
      expect(settings.dischargeUtp, closeTo(-10.0, 0.1));
    });

    test('parses battery type — LFP', () {
      final data = _buildSettingsFrame(batteryType: 0);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.batteryType, 0);
      expect(settings.batteryTypeName, 'LiFePO4');
    });

    test('parses battery type — Li-ion', () {
      final data = _buildSettingsFrame(batteryType: 1);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.batteryType, 1);
      expect(settings.batteryTypeName, 'Li-ion');
    });

    test('parses battery type — LTO', () {
      final data = _buildSettingsFrame(batteryType: 2);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      expect(settings.batteryType, 2);
      expect(settings.batteryTypeName, 'LTO');
    });
  });

  group('parseSettings — JK02_32S', () {
    test('parses with mainOffset = 32', () {
      final data = _buildSettingsFrame(
        numCells: 32,
        nominalCapacityMah: 310000,
        batteryType: 0,
        mainOffset: 32,
      );
      final settings = parseSettings(data, JkProtocol.jk02_32s);
      expect(settings.numCells, 32);
      expect(settings.nominalCapacity, closeTo(310.0, 0.001));
      expect(settings.batteryType, 0);
    });
  });

  group('JkSettings helper methods', () {
    test('toString includes key info', () {
      final data = _buildSettingsFrame(numCells: 16, nominalCapacityMah: 280000);
      final settings = parseSettings(data, JkProtocol.jk02_24s);
      final str = settings.toString();
      expect(str, contains('cells=16'));
      expect(str, contains('280.0'));
      expect(str, contains('LiFePO4'));
    });
  });
}
