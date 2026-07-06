import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jk_bms/src/parsers/daly_parser.dart';
import 'package:jk_bms/src/protocol/daly_constants.dart';
import 'package:jk_bms/src/protocol/daly_frame_assembler.dart';

/// Build a Daly frame with given command and data bytes.
DalyFrame _makeFrame(int command, List<int> dataBytes) {
  assert(dataBytes.length == 8, 'Daly data must be exactly 8 bytes');
  return DalyFrame(
    command: command,
    data: Uint8List.fromList(dataBytes),
    checksumValid: true,
  );
}

void main() {
  group('parseDalySoc (0x90)', () {
    test('parses voltage, current, and SOC correctly', () {
      final data = DalyBmsData();
      // Total voltage: 264 (raw) × 0.1 = 26.4V
      // Gather voltage: 0 (ignored)
      // Current: 30200 (raw) → (30200 - 30000) × 0.1 = 20.0A
      // SOC: 228 (raw) × 0.1 = 22.8%
      final frame = _makeFrame(kDalyCmdSoc, [
        0x01, 0x08, // total voltage: 264 = 0x0108
        0x00, 0x00, // gather voltage (ignored)
        0x75, 0xF8, // current: 30200 = 0x75F8
        0x00, 0xE4, // SOC: 228 = 0x00E4
      ]);

      parseDalySoc(frame, data);

      expect(data.totalVoltage, closeTo(26.4, 0.1));
      expect(data.current, closeTo(20.0, 0.1));
      expect(data.soc, closeTo(22.8, 0.1));
      expect(data.socReceived, isTrue);
    });

    test('parses negative current (discharge)', () {
      final data = DalyBmsData();
      // Current: 29800 (raw) → (29800 - 30000) × 0.1 = -20.0A
      final frame = _makeFrame(kDalyCmdSoc, [
        0x01, 0x08, // voltage: 264
        0x00, 0x00,
        0x74, 0x68, // current: 29800 = 0x7468
        0x03, 0x20, // SOC: 800 = 80%
      ]);

      parseDalySoc(frame, data);

      expect(data.current, closeTo(-20.0, 0.1));
      expect(data.soc, closeTo(80.0, 0.1));
    });
  });

  group('parseDalyMosStatus (0x93)', () {
    test('parses charging and discharging MOS as ON', () {
      final data = DalyBmsData();
      // Mode: 1 (charging)
      // Charge MOS: 1 (on)
      // Discharge MOS: 1 (on)
      // Cycle count: 2
      // Remaining capacity: 68400 mAh = 68.4 Ah
      final rawCap = 68400; // 0x00010B30
      final frame = _makeFrame(kDalyCmdMosStatus, [
        0x01, // mode: charging
        0x01, // charge MOS: ON
        0x01, // discharge MOS: ON
        0x02, // cycle count: 2
        (rawCap >> 24) & 0xFF,
        (rawCap >> 16) & 0xFF,
        (rawCap >> 8) & 0xFF,
        rawCap & 0xFF,
      ]);

      parseDalyMosStatus(frame, data);

      expect(data.chargingEnabled, isTrue);
      expect(data.dischargingEnabled, isTrue);
      expect(data.bmsLife, equals(2));
      expect(data.capacityRemaining, closeTo(68.4, 0.1));
      expect(data.statusMode, equals(1));
      expect(data.mosStatusReceived, isTrue);
    });

    test('parses MOS as OFF when bytes are 0', () {
      final data = DalyBmsData();
      final frame = _makeFrame(kDalyCmdMosStatus, [
        0x00, // mode: stationary
        0x00, // charge MOS: OFF
        0x00, // discharge MOS: OFF
        0x00, // cycle count: 0
        0x00, 0x00, 0x00, 0x00, // capacity: 0
      ]);

      parseDalyMosStatus(frame, data);

      expect(data.chargingEnabled, isFalse);
      expect(data.dischargingEnabled, isFalse);
      expect(data.bmsLife, equals(0));
      expect(data.capacityRemaining, equals(0.0));
      expect(data.statusMode, equals(0));
    });

    test('parses cycle count up to 255', () {
      final data = DalyBmsData();
      final frame = _makeFrame(kDalyCmdMosStatus, [
        0x02, // mode: discharging
        0x01, 0x01,
        0xFF, // cycle count: 255
        0x00, 0x00, 0x00, 0x00,
      ]);

      parseDalyMosStatus(frame, data);

      expect(data.bmsLife, equals(255));
    });

    test('parses large remaining capacity', () {
      final data = DalyBmsData();
      // 200000 mAh = 200.0 Ah
      final rawCap = 200000; // 0x00030D40
      final frame = _makeFrame(kDalyCmdMosStatus, [
        0x01, 0x01, 0x01, 0x05,
        (rawCap >> 24) & 0xFF,
        (rawCap >> 16) & 0xFF,
        (rawCap >> 8) & 0xFF,
        rawCap & 0xFF,
      ]);

      parseDalyMosStatus(frame, data);

      expect(data.capacityRemaining, closeTo(200.0, 0.1));
    });
  });

  group('parseDalyMinMaxVoltage (0x91)', () {
    test('parses max and min cell voltage', () {
      final data = DalyBmsData();
      // Max: 3313 mV (cell 5)
      // Min: 3309 mV (cell 3)
      final frame = _makeFrame(kDalyCmdMinMaxVoltage, [
        0x0C, 0xF1, // max: 3313 = 0x0CF1
        0x05, // max cell: 5
        0x0C, 0xED, // min: 3309 = 0x0CED
        0x03, // min cell: 3
        0x00, 0x00,
      ]);

      parseDalyMinMaxVoltage(frame, data);

      expect(data.maxCellVoltage, closeTo(3.313, 0.001));
      expect(data.maxVoltageCellNumber, equals(5));
      expect(data.minCellVoltage, closeTo(3.309, 0.001));
      expect(data.minVoltageCellNumber, equals(3));
    });
  });

  group('parseDalyMinMaxTemp (0x92)', () {
    test('parses max and min temperature with offset', () {
      final data = DalyBmsData();
      // Max: 69 → 69 - 40 = 29°C
      // Min: 67 → 67 - 40 = 27°C
      final frame = _makeFrame(kDalyCmdMinMaxTemp, [
        69, // max temp raw
        0x01, // max sensor number
        67, // min temp raw
        0x02, // min sensor number
        0x00, 0x00, 0x00, 0x00,
      ]);

      parseDalyMinMaxTemp(frame, data);

      expect(data.maxTemperature, equals(29.0));
      expect(data.minTemperature, equals(27.0));
    });
  });

  group('parseDalyStatusInfo (0x94)', () {
    test('parses cell count, NTC count, and cycle count', () {
      final data = DalyBmsData();
      final frame = _makeFrame(kDalyCmdStatusInfo, [
        0x08, // 8 cells
        0x02, // 2 NTC sensors
        0x00, // charger
        0x00, // load
        0x00, 0x00, // DIO
        0x02, // cycle count: 2
        0x4A, // unknown
      ]);

      parseDalyStatusInfo(frame, data);

      expect(data.cellCount, equals(8));
      expect(data.ntcCount, equals(2));
      expect(data.cycleCount, equals(2));
    });
  });

  group('parseDalyRatedParams (0x50)', () {
    test('parses rated capacity and voltage', () {
      final data = DalyBmsData();
      final frame = _makeFrame(kDalyCmdRatedParams, [
        0x00, 0x04, 0x93, 0xE0, // 300000 -> 300.0 Ah
        0x00, 0x00, 0x0C, 0x80, // 3200 -> 32.0 V
      ]);

      parseDalyRatedParams(frame, data);

      expect(data.ratedCapacity, closeTo(300.0, 0.1));
      expect(data.ratedVoltage, closeTo(32.0, 0.1));
    });
  });

  group('parseDalyBatteryDetails (0x53)', () {
    test('parses production date', () {
      final data = DalyBmsData();
      final frame = _makeFrame(kDalyCmdBatteryDetails, [
        0x00, 0x00, 
        0x19, // 25 -> 2025
        0x08, // August
        0x07, // 7th
        0xFF, 0xFF, 0x0A,
      ]);

      parseDalyBatteryDetails(frame, data);

      expect(data.productionDate, equals('2025-08-07'));
    });
  });

  group('parseDalyBatteryCode (0x57)', () {
    test('accumulates multi-frame ASCII string', () {
      final data = DalyBmsData();
      
      // Send frames out of order to verify sorting
      parseDalyBatteryCode(_makeFrame(kDalyCmdBatteryCode, [
        0x02, 0x2D, 0x32, 0x34, 0x53, 0x32, 0x30, 0x30 // "-24S200"
      ]), data);
      
      parseDalyBatteryCode(_makeFrame(kDalyCmdBatteryCode, [
        0x01, 0x52, 0x32, 0x34, 0x54, 0x4D, 0x31, 0x41 // "R24TM1A"
      ]), data);
      
      parseDalyBatteryCode(_makeFrame(kDalyCmdBatteryCode, [
        0x03, 0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 // "A\0\0\0\0\0\0"
      ]), data);

      expect(data.batteryCode, equals('R24TM1A-24S200A'));
    });
  });

  group('parseDalyCellVoltages (0x95)', () {
    test('parses first frame of cell voltages', () {
      final data = DalyBmsData();
      // Frame 1: cells 1-3
      final frame = _makeFrame(kDalyCmdCellVoltages, [
        0x01, // frame number: 1
        0x0C, 0xF0, // cell 1: 3312 mV
        0x0C, 0xF1, // cell 2: 3313 mV
        0x0C, 0xEF, // cell 3: 3311 mV
        0x00,
      ]);

      parseDalyCellVoltages(frame, data);

      expect(data.cellVoltages.length, greaterThanOrEqualTo(3));
      expect(data.cellVoltages[0], closeTo(3.312, 0.001));
      expect(data.cellVoltages[1], closeTo(3.313, 0.001));
      expect(data.cellVoltages[2], closeTo(3.311, 0.001));
    });

    test('parses second frame of cell voltages', () {
      final data = DalyBmsData();
      // First frame
      parseDalyCellVoltages(
        _makeFrame(kDalyCmdCellVoltages, [
          0x01, 0x0C, 0xF0, 0x0C, 0xF1, 0x0C, 0xEF, 0x00,
        ]),
        data,
      );
      // Second frame
      parseDalyCellVoltages(
        _makeFrame(kDalyCmdCellVoltages, [
          0x02, // frame number: 2
          0x0C, 0xF0, // cell 4: 3312 mV
          0x0C, 0xF1, // cell 5: 3313 mV
          0x0C, 0xED, // cell 6: 3309 mV
          0x00,
        ]),
        data,
      );

      expect(data.cellVoltages.length, greaterThanOrEqualTo(6));
      expect(data.cellVoltages[3], closeTo(3.312, 0.001));
      expect(data.cellVoltages[4], closeTo(3.313, 0.001));
      expect(data.cellVoltages[5], closeTo(3.309, 0.001));
    });
  });

  group('Data accumulation', () {
    test('toCellStatus reflects MOS data when parsed before SOC', () {
      final data = DalyBmsData();

      // Parse MOS status FIRST (like real request order)
      parseDalyFrame(
        _makeFrame(kDalyCmdMosStatus, [
          0x01, // charging
          0x01, // charge MOS: ON
          0x01, // discharge MOS: ON
          0xA5, // bmsLife: 165 (heartbeat, NOT cycle count!)
          0x00, 0x01, 0x0B, 0x30, // 68400 mAh = 68.4 Ah
        ]),
        data,
      );

      // Then parse status info (contains actual cycle count)
      parseDalyFrame(
        _makeFrame(kDalyCmdStatusInfo, [
          8, 2, // 8 cells, 2 NTC
          0x01, 0x01, // charger, load
          0x00, 0x00, // DI/O
          0x02, 0x00, // cycle count: 2 (byte 6)
        ]),
        data,
      );

      // Then parse SOC
      parseDalyFrame(
        _makeFrame(kDalyCmdSoc, [
          0x01, 0x08, // voltage: 26.4V
          0x00, 0x00,
          0x75, 0xF8, // current: 20.0A
          0x00, 0xE4, // SOC: 22.8%
        ]),
        data,
      );

      final status = data.toCellStatus();

      // MOS data should be present
      expect(status.chargingEnabled, isTrue,
          reason: 'Charging MOS should be ON');
      expect(status.dischargingEnabled, isTrue,
          reason: 'Discharging MOS should be ON');
      expect(status.cycleCount, equals(2),
          reason: 'Cycle count should be 2 (from 0x94)');
      expect(data.bmsLife, equals(165),
          reason: 'BMS life should be 165 (heartbeat from 0x93)');
      expect(status.capacityRemaining, closeTo(68.4, 0.1),
          reason: 'Remaining capacity should be 68.4 Ah');

      // SOC data should be present
      expect(status.totalVoltage, closeTo(26.4, 0.1));
      expect(status.current, closeTo(20.0, 0.1));
      expect(status.soc, equals(23)); // 22.8 rounds to 23
    });

    test('toCellStatus shows default MOS when NOT parsed', () {
      final data = DalyBmsData();

      // Parse ONLY SOC (old buggy order)
      parseDalyFrame(
        _makeFrame(kDalyCmdSoc, [
          0x01, 0x08, 0x00, 0x00, 0x75, 0xF8, 0x00, 0xE4,
        ]),
        data,
      );

      final status = data.toCellStatus();

      // MOS should be default (false) since 0x93 not yet received
      expect(status.chargingEnabled, isFalse);
      expect(status.dischargingEnabled, isFalse);
      expect(status.cycleCount, equals(0));
      expect(data.mosStatusReceived, isFalse);
    });

    test('full sequence accumulates all data correctly', () {
      final data = DalyBmsData();

      // 1. MOS status
      parseDalyFrame(
        _makeFrame(kDalyCmdMosStatus, [
          0x01, 0x01, 0x01, 0xA5, // bmsLife=165
          0x00, 0x01, 0x0B, 0x30, // 68.4 Ah
        ]),
        data,
      );

      // 2. Status info (with cycle count at byte 6)
      parseDalyFrame(
        _makeFrame(kDalyCmdStatusInfo, [
          8, 2, 0x01, 0x01,
          0x00, 0x00,
          0x02, 0x00, // cycle count: 2 (byte 6)
        ]),
        data,
      );

      // 3. Min/Max temp
      parseDalyFrame(
        _makeFrame(kDalyCmdMinMaxTemp, [
          69, 0x01, 67, 0x02, 0x00, 0x00, 0x00, 0x00,
        ]),
        data,
      );

      // 3. Min/Max voltage
      parseDalyFrame(
        _makeFrame(kDalyCmdMinMaxVoltage, [
          0x0C, 0xF1, 0x05, 0x0C, 0xED, 0x03, 0x00, 0x00,
        ]),
        data,
      );

      // 4. Cell voltages (frame 1)
      parseDalyFrame(
        _makeFrame(kDalyCmdCellVoltages, [
          0x01, 0x0C, 0xF0, 0x0C, 0xF1, 0x0C, 0xEF, 0x00,
        ]),
        data,
      );

      // 5. SOC (last)
      parseDalyFrame(
        _makeFrame(kDalyCmdSoc, [
          0x01, 0x08, 0x00, 0x00, 0x75, 0xF8, 0x00, 0xE4,
        ]),
        data,
      );

      final status = data.toCellStatus();

      // All accumulated data should be present
      expect(status.chargingEnabled, isTrue);
      expect(status.dischargingEnabled, isTrue);
      expect(status.cycleCount, equals(2));
      expect(status.capacityRemaining, closeTo(68.4, 0.1));
      expect(status.temperature1, equals(29.0));
      expect(status.temperature2, equals(27.0));
      expect(status.maxVoltageCellNumber, equals(5));
      expect(status.minVoltageCellNumber, equals(3));
      expect(status.totalVoltage, closeTo(26.4, 0.1));
      expect(status.current, closeTo(20.0, 0.1));
      expect(status.soc, equals(23));
      expect(status.enabledCellCount, equals(8));
      expect(status.cellVoltages.length, greaterThanOrEqualTo(3));

      // Device info
      final info = data.toDeviceInfo();
      expect(info.deviceName, equals('Daly BMS 8S'));
    });
  });
}
