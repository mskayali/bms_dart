import 'dart:typed_data';

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

  /// Cycle count.
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
      fullCapacity: 0, // Not available in basic Daly responses
      cycleCount: cycleCount,
      totalCycleCapacity: 0,
      soh: 100,
      totalRuntime: 0,
      chargingEnabled: chargingEnabled,
      dischargingEnabled: dischargingEnabled,
      prechargeEnabled: false,
      balancerWorking: false,
      heatingEnabled: false,
    );
  }

  /// Create a basic [JkDeviceInfo] from Daly data.
  JkDeviceInfo toDeviceInfo() {
    return JkDeviceInfo(
      rawData: const [],
      deviceName: 'Daly BMS ${cellCount}S',
      hardwareVersion: '-',
      softwareVersion: '-',
      serialNumber: '-',
      manufacturingDate: '-',
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
/// Data layout (from batmon-ha, struct format `>b??Bl`):
/// - Byte 0: Mode (0=stationary, 1=charging, 2=discharging)
/// - Byte 1: Charge MOS (bool)
/// - Byte 2: Discharge MOS (bool)
/// - Byte 3: BMS life (cycles)
/// - Bytes 4-7: Remaining capacity (×0.001 Ah)
void parseDalyMosStatus(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Byte 0: Mode
  // Byte 1: Charge MOS state (1=on)
  data.chargingEnabled = d[1] != 0;
  // Byte 2: Discharge MOS state (1=on)
  data.dischargingEnabled = d[2] != 0;
  // Byte 3: BMS life (cycle count)
  data.cycleCount = d[3];
  // Bytes 4-7: Remaining capacity (unsigned 32-bit BE, ×0.001 Ah)
  final rawCapacity = (d[4] << 24) | (d[5] << 16) | (d[6] << 8) | d[7];
  data.capacityRemaining = rawCapacity * 0.001;
}

/// Parse a Daly 0x94 (Status Info) response.
void parseDalyStatusInfo(DalyFrame frame, DalyBmsData data) {
  final d = frame.data;
  // Byte 0: Number of cells
  data.cellCount = d[0];
  // Byte 1: Number of NTC sensors
  data.ntcCount = d[1];
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

/// Dispatch a Daly frame to the appropriate parser.
void parseDalyFrame(DalyFrame frame, DalyBmsData data) {
  switch (frame.command) {
    case kDalyCmdSoc:
      parseDalySoc(frame, data);
    case kDalyCmdMinMaxVoltage:
      parseDalyMinMaxVoltage(frame, data);
    case kDalyCmdMinMaxTemp:
      parseDalyMinMaxTemp(frame, data);
    case kDalyCmdMosStatus:
      parseDalyMosStatus(frame, data);
    case kDalyCmdStatusInfo:
      parseDalyStatusInfo(frame, data);
    case kDalyCmdCellVoltages:
      parseDalyCellVoltages(frame, data);
    case kDalyCmdCellTemps:
      parseDalyCellTemps(frame, data);
    case kDalyCmdFailure:
      parseDalyFailure(frame, data);
  }
}

/// Read unsigned 16-bit big-endian value.
int _u16(Uint8List data, int offset) {
  return (data[offset] << 8) | data[offset + 1];
}
