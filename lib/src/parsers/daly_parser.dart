import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/cell_status.dart';
import '../models/device_info.dart';
import '../protocol/daly_constants.dart';
import '../protocol/daly_frame_assembler.dart';

/// Accumulated Daly BMS data from multiple response commands.
///
/// Since Daly BMS sends data across separate commands (0x90, 0x91, etc.),
/// this class accumulates parsed values until a complete picture is formed.
class DalyBmsData {
  /// Pack voltage in volts.
  double totalVoltage = 0;

  /// Pack current in amps (negative = discharge).
  double current = 0;

  /// State of charge in percent.
  double soc = 0;

  /// Max cell voltage in volts.
  double maxCellVoltage = 0;

  /// Max voltage cell number (1-based).
  int maxVoltageCellNumber = 0;

  /// Min cell voltage in volts.
  double minCellVoltage = 0;

  /// Min voltage cell number (1-based).
  int minVoltageCellNumber = 0;

  /// Max temperature in °C.
  double maxTemperature = 0;

  /// Min temperature in °C.
  double minTemperature = 0;

  /// Charging MOS state.
  bool chargingEnabled = false;

  /// Discharging MOS state.
  bool dischargingEnabled = false;

  /// BMS status mode: 0=stationary, 1=charging, 2=discharging.
  int statusMode = 0;

  /// BMS life counter (heartbeat, 0-255, from 0x93 byte 3).
  /// This is NOT the battery cycle count.
  int bmsLife = 0;

  /// Cycle count (actual battery charge/discharge cycles).
  int cycleCount = 0;

  /// Remaining capacity in Ah.
  double capacityRemaining = 0;

  /// Number of cells.
  int cellCount = 0;

  /// Number of NTC sensors.
  int ntcCount = 0;

  /// Individual cell voltages in volts.
  List<double> cellVoltages = [];

  /// Individual temperatures in °C.
  List<double> temperatures = [];

  /// Error/failure bitmask.
  int errors = 0;

  /// Whether at least one MOS status response has been received.
  bool mosStatusReceived = false;

  /// Whether at least one SOC response has been received.
  bool socReceived = false;

  /// Battery code / model string (from 0x57 multi-frame ASCII).
  String batteryCode = '';

  /// Software Version (from 0x62 multi-frame ASCII).
  String softwareVersion = '';

  /// Hardware Version (from 0x63 multi-frame ASCII).
  String hardwareVersionString = '';

  /// Unknown 0x54 (multi-frame ASCII).
  String unknown54 = '';

  /// Production / manufacturing date string (from 0x53).
  String productionDate = '';

  /// Rated (nominal/full) capacity in Ah (from 0x50).
  double ratedCapacity = 0;

  /// Rated (nominal) voltage in V (from 0x50).
  double ratedVoltage = 0;

  /// Accumulated 0x57 battery code frame fragments.
  /// Key=frame number, Value=ASCII bytes.
  final Map<int, String> _batteryCodeFrames = {};

  final Map<int, String> _softwareVersionFrames = {};
  final Map<int, String> _hardwareVersionFrames = {};
  final Map<int, String> _unknown54Frames = {};

  /// Convert accumulated data to a [JkCellStatus] model.
  JkCellStatus toCellStatus() {
    final avgVoltage = cellVoltages.isNotEmpty
        ? cellVoltages.reduce((a, b) => a + b) / cellVoltages.length
        : totalVoltage / (cellCount > 0 ? cellCount : 1);

    final deltaVoltage = maxCellVoltage - minCellVoltage;

    return JkCellStatus(
      cellVoltages: cellVoltages,
      cellResistances: List.filled(cellVoltages.length, 0.0),
      enabledCellCount: cellCount > 0 ? cellCount : cellVoltages.length,
      averageCellVoltage: avgVoltage,
      deltaCellVoltage: deltaVoltage,
      maxVoltageCellNumber: maxVoltageCellNumber,
      minVoltageCellNumber: minVoltageCellNumber,
      totalVoltage: totalVoltage,
      current: current,
      power: totalVoltage * current,
      temperature1: maxTemperature,
      temperature2: minTemperature,
      mosTemperature: 0,
      errors: errors,
      balanceCurrent: 0,
      balancerAction: 0,
      soc: soc.round(),
      capacityRemaining: capacityRemaining,
      fullCapacity: ratedCapacity,
      cycleCount: cycleCount,
      totalCycleCapacity: 0,
      soh: 100,
      chargingEnabled: chargingEnabled,
      dischargingEnabled: dischargingEnabled,
      prechargeEnabled: false,
      balancerWorking: false,
      heatingEnabled: false,
    );
  }

  /// Create a [JkDeviceInfo] from accumulated Daly data.
  JkDeviceInfo toDeviceInfo() {
    // Determine the best mapping based on what was received.
    // Sometimes 0x57 is hardware version, sometimes 0x63. 
    final hw = hardwareVersionString.isNotEmpty ? hardwareVersionString : batteryCode;
    final sn = unknown54.isNotEmpty ? unknown54 : batteryCode;
    final sw = softwareVersion.isNotEmpty ? softwareVersion : '-';

    return JkDeviceInfo(
      rawData: const [],
      deviceName: 'Daly BMS ${cellCount > 0 ? '${cellCount}S' : ''}',
      hardwareVersion: hw.isNotEmpty ? hw : '-',
      softwareVersion: sw,
      serialNumber: sn.isNotEmpty && sn != hw ? sn : '-',
      manufacturingDate: productionDate.isNotEmpty ? productionDate : '-',
    );
  }
}

/// Parse a Daly 0x90 (SOC/Voltage/Current) response.
void parseDalySoc(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Bytes 0-1: Total voltage (×0.1V)
  data.totalVoltage = _u16(d, 0) * kDalyVoltageScale;
  // Bytes 2-3: Gather voltage (often same or reserved)
  // Bytes 4-5: Current (offset 30000, ×0.1A)
  final rawCurrent = _u16(d, 4);
  data.current = (rawCurrent - kDalyCurrentOffset) * kDalyCurrentScale;
  // Bytes 6-7: SOC (×0.1%)
  data.soc = _u16(d, 6) * kDalySocScale;
  data.socReceived = true;
}

/// Parse a Daly 0x91 (Min/Max Cell Voltage) response.
void parseDalyMinMaxVoltage(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Bytes 0-1: Max cell voltage (mV)
  data.maxCellVoltage = _u16(d, 0) * kDalyCellVoltageScale;
  // Byte 2: Max voltage cell number
  data.maxVoltageCellNumber = d[2];
  // Bytes 3-4: Min cell voltage (mV)
  data.minCellVoltage = _u16(d, 3) * kDalyCellVoltageScale;
  // Byte 5: Min voltage cell number
  data.minVoltageCellNumber = d[5];
}

/// Parse a Daly 0x92 (Min/Max Temperature) response.
void parseDalyMinMaxTemp(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Byte 0: Max temp (offset 40)
  data.maxTemperature = (d[0] - kDalyTempOffset).toDouble();
  // Byte 1: Max temp sensor number
  // Byte 2: Min temp (offset 40)
  data.minTemperature = (d[2] - kDalyTempOffset).toDouble();
}

/// Parse a Daly 0x93 (MOS Status) response.
///
/// Python struct format: `>b??BL` (big-endian)
/// Data layout (8 bytes):
/// - Byte 0: Mode (0=stationary, 1=charging, 2=discharging)
/// - Byte 1: Charge MOS (bool, 1=on)
/// - Byte 2: Discharge MOS (bool, 1=on)
/// - Byte 3: BMS life (heartbeat counter, 0-255, NOT cycle count!)
/// - Bytes 4-7: Remaining capacity (unsigned 32-bit BE, ×0.001 Ah)
void parseDalyMosStatus(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Byte 0: Mode (0=stationary, 1=charging, 2=discharging)
  data.statusMode = d[0];
  // Byte 1: Charge MOS state (1=on, 0=off)
  data.chargingEnabled = d[1] != 0;
  // Byte 2: Discharge MOS state (1=on, 0=off)
  data.dischargingEnabled = d[2] != 0;
  // Byte 3: BMS life (heartbeat, NOT battery cycle count)
  data.bmsLife = d[3];
  // Bytes 4-7: Remaining capacity (unsigned 32-bit BE, ×0.001 Ah)
  final rawCapacity = (d[4] << 24) | (d[5] << 16) | (d[6] << 8) | d[7];
  data.capacityRemaining = rawCapacity * 0.001;
  data.mosStatusReceived = true;
}

/// Parse a Daly 0x94 (Status Info) response.
///
/// Verified from raw data:
/// - Byte 0: Number of cell strings (8)
/// - Byte 1: Number of NTC sensors (2)
/// - Byte 2: Charger status
/// - Byte 3: Load status
/// - Byte 4-5: Reserved/DIO
/// - Byte 6: Cycle count (SINGLE BYTE, 0-255)
/// - Byte 7: Unknown (0x4A observed)
void parseDalyStatusInfo(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Byte 0: Number of cells
  data.cellCount = d[0];
  // Byte 1: Number of NTC sensors
  data.ntcCount = d[1];
  // Byte 6: Cycle count (single byte, verified from raw data)
  data.cycleCount = d[6];
}

/// Parse a Daly 0x95 (Cell Voltages) response.
///
/// This command may return multiple 13-byte frames if there are many cells.
/// Each frame contains up to 3 cell voltages:
/// - Byte 0: Frame number (1-based)
/// - Bytes 1-2: Cell voltage 1 (mV)
/// - Bytes 3-4: Cell voltage 2 (mV)
/// - Bytes 5-6: Cell voltage 3 (mV)
void parseDalyCellVoltages(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final frameNum = d[0]; // 1-based frame number

  // Ensure cell voltages list is large enough
  final startIdx = (frameNum - 1) * 3;

  for (int i = 0; i < 3; i++) {
    final offset = 1 + (i * 2);
    if (offset + 1 < d.length) {
      final mv = _u16(d, offset);
      if (mv > 0 && mv < 5000) {
        // Valid cell voltage (0-5V)
        final cellIdx = startIdx + i;
        while (data.cellVoltages.length <= cellIdx) {
          data.cellVoltages.add(0);
        }
        data.cellVoltages[cellIdx] = mv * kDalyCellVoltageScale;
      }
    }
  }
}

/// Parse a Daly 0x96 (Cell Temperatures) response.
void parseDalyCellTemps(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final frameNum = d[0]; // 1-based frame number
  final startIdx = (frameNum - 1) * 7;

  for (int i = 1; i < 8 && i < d.length; i++) {
    if (d[i] > 0) {
      final tempIdx = startIdx + (i - 1);
      while (data.temperatures.length <= tempIdx) {
        data.temperatures.add(0);
      }
      data.temperatures[tempIdx] = (d[i] - kDalyTempOffset).toDouble();
    }
  }
}

/// Parse a Daly 0x98 (Failure Status) response.
void parseDalyFailure(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Build a bitmask from failure bytes
  data.errors = 0;
  for (int i = 0; i < d.length && i < 8; i++) {
    data.errors |= (d[i] & 0xFF) << (i * 8);
  }
}

/// Parse a Daly 0x50 (Rated Parameters) response.
///
/// Verified from raw data: [00 04 93 e0 00 00 0c 80]
/// - Bytes 0-3: Rated capacity (u32 BE, ×0.001 Ah) → 300000 = 300.0 Ah
/// - Bytes 4-7: Rated voltage (u32 BE, ×0.01 V) → 3200 = 32.0 V
void parseDalyRatedParams(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final rawCapacity = (d[0] << 24) | (d[1] << 16) | (d[2] << 8) | d[3];
  data.ratedCapacity = rawCapacity * 0.001;
  final rawVoltage = (d[4] << 24) | (d[5] << 16) | (d[6] << 8) | d[7];
  data.ratedVoltage = rawVoltage * 0.01;
}

/// Parse a Daly 0x53 (Battery Details) response.
///
/// Verified from raw data: [00 00 19 08 07 ff ff 0a]
/// - Bytes 0-1: Reserved
/// - Byte 2: Production year (0x19 = 25 → 2025)
/// - Byte 3: Production month (0x08 = August)
/// - Byte 4: Production day (0x07 = 7th)
/// - Bytes 5-7: Reserved/padding
void parseDalyBatteryDetails(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final year = 2000 + d[2];
  final month = d[3];
  final day = d[4];
  if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
    data.productionDate =
        '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
  }
}

/// Parse a Daly 0x57 (Battery Code) response.
///
/// Multi-frame ASCII: byte 0 = frame number (1-5), bytes 1-7 = ASCII chars.
/// Verified from raw data:
/// - Frame 1: [01 52 32 34 54 4d 31 41] → "R24TM1A"
/// - Frame 2: [02 2d 32 34 53 32 30 30] → "-24S200"
/// - Frame 3: [03 41 00 00 00 00 00 00] → "A"
/// → Full string: "R24TM1A-24S200A"
void parseDalyBatteryCode(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final frameNum = d[0];

  // Extract ASCII chars (bytes 1-7), stop at null terminator
  final buf = StringBuffer();
  for (int i = 1; i < 8; i++) {
    if (d[i] == 0) break;
    buf.writeCharCode(d[i]);
  }

  data._batteryCodeFrames[frameNum] = buf.toString();

  // Rebuild full battery code from all received frames, in order
  final sorted = data._batteryCodeFrames.keys.toList()..sort();
  final full = StringBuffer();
  for (final key in sorted) {
    full.write(data._batteryCodeFrames[key]);
  }
  data.batteryCode = full.toString();
}

/// Parse a Daly 0x62 (Software Version) response.
void parseDalySoftwareVersion(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final frameNum = d[0];

  final buf = StringBuffer();
  for (int i = 1; i < 8; i++) {
    if (d[i] == 0) break;
    buf.writeCharCode(d[i]);
  }

  data._softwareVersionFrames[frameNum] = buf.toString();
  final sorted = data._softwareVersionFrames.keys.toList()..sort();
  final full = StringBuffer();
  for (final key in sorted) {
    full.write(data._softwareVersionFrames[key]);
  }
  data.softwareVersion = full.toString();
}

/// Parse a Daly 0x63 (Hardware Version) response.
void parseDalyHardwareVersion(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final frameNum = d[0];

  final buf = StringBuffer();
  for (int i = 1; i < 8; i++) {
    if (d[i] == 0) break;
    buf.writeCharCode(d[i]);
  }

  data._hardwareVersionFrames[frameNum] = buf.toString();
  final sorted = data._hardwareVersionFrames.keys.toList()..sort();
  final full = StringBuffer();
  for (final key in sorted) {
    full.write(data._hardwareVersionFrames[key]);
  }
  data.hardwareVersionString = full.toString();
}

/// Parse a Daly 0x54 (Unknown / Serial Number) response.
void parseDalyUnknown54(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final frameNum = d[0];

  final buf = StringBuffer();
  for (int i = 1; i < 8; i++) {
    if (d[i] == 0) break;
    buf.writeCharCode(d[i]);
  }

  data._unknown54Frames[frameNum] = buf.toString();
  final sorted = data._unknown54Frames.keys.toList()..sort();
  final full = StringBuffer();
  for (final key in sorted) {
    full.write(data._unknown54Frames[key]);
  }
  data.unknown54 = full.toString();
}

/// Dispatch a Daly frame to the appropriate parser.
void parseDalyFrame(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  final hex = d.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  final cmdHex = '0x${frame.command.toRadixString(16).padLeft(2, '0')}';

  switch (frame.command) {
    case kDalyCmdSoc:
      parseDalySoc(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → V=${data.totalVoltage}, '
          'I=${data.current}, SOC=${data.soc}');
    case kDalyCmdMinMaxVoltage:
      parseDalyMinMaxVoltage(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → maxV=${data.maxCellVoltage}, '
          'minV=${data.minCellVoltage}');
    case kDalyCmdMinMaxTemp:
      parseDalyMinMaxTemp(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → maxT=${data.maxTemperature}, '
          'minT=${data.minTemperature}');
    case kDalyCmdMosStatus:
      parseDalyMosStatus(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → mode=${data.statusMode}, '
          'chg=${data.chargingEnabled}, dischg=${data.dischargingEnabled}, '
          'bmsLife=${data.bmsLife}, capRemain=${data.capacityRemaining}Ah');
    case kDalyCmdStatusInfo:
      parseDalyStatusInfo(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → cells=${data.cellCount}, '
          'ntc=${data.ntcCount}, cycleCount=${data.cycleCount}');
    case kDalyCmdCellVoltages:
      parseDalyCellVoltages(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → '
          '${data.cellVoltages.length} cells');
    case kDalyCmdCellTemps:
      parseDalyCellTemps(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → '
          '${data.temperatures.length} temps');
    case kDalyCmdFailure:
      parseDalyFailure(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → errors=${data.errors}');
    case kDalyCmdRatedParams:
      parseDalyRatedParams(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → ratedCap=${data.ratedCapacity}Ah, '
          'ratedV=${data.ratedVoltage}V');
    case kDalyCmdBatteryDetails:
      parseDalyBatteryDetails(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → date=${data.productionDate}');
    case kDalyCmdBatteryCode:
      parseDalyBatteryCode(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → code="${data.batteryCode}"');
    case kDalyCmdSoftwareVersion:
      parseDalySoftwareVersion(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → sw="${data.softwareVersion}"');
    case kDalyCmdHardwareVersion:
      parseDalyHardwareVersion(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → hw="${data.hardwareVersionString}"');
    case kDalyCmdUnknown54:
      parseDalyUnknown54(frame, data);
      debugPrint('[DALY] $cmdHex RAW=[$hex] → u54="${data.unknown54}"');
    default:
      debugPrint('[DALY] $cmdHex RAW=[$hex] (unhandled)');
  }
}

/// Read unsigned 16-bit big-endian value.
int _u16(Uint8List data, int offset) {
  return (data[offset] << 8) | data[offset + 1];
}
