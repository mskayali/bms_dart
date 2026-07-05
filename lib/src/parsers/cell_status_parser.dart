import 'dart:typed_data';

import '../models/cell_status.dart';
import '../protocol/byte_reader.dart';
import '../protocol/constants.dart';

/// Parses a JK02 cell/status frame (frame type `0x02`).
///
/// Supports both [JkProtocol.jk02_24s] and [JkProtocol.jk02_32s] protocols,
/// applying the correct cell and main offsets per the specification.
///
/// ```dart
/// final status = parseCellStatus(frameData, JkProtocol.jk02_32s);
/// print('SOC: ${status.soc}%');
/// print('Total voltage: ${status.totalVoltage}V');
/// ```
JkCellStatus parseCellStatus(Uint8List data, JkProtocol protocol) {
  final cellOffset = protocol.cellOffset;
  final mainOffset = protocol.mainOffset;
  final cellCount = protocol.cellCount;

  // --- Cell voltages (offset 6, 2 bytes each, u16le, × 0.001 V) ---
  final cellVoltages = <double>[];
  for (int i = 0; i < cellCount; i++) {
    cellVoltages.add(u16le(data, 6 + i * 2) * kVoltageScale);
  }

  // --- Enabled cell bitmask (offset 54 + cellOffset, u32le) ---
  final enabledBitmask = u32le(data, 54 + cellOffset);
  int enabledCellCount = 0;
  for (int i = 0; i < 32; i++) {
    if ((enabledBitmask >> i) & 1 == 1) enabledCellCount++;
  }

  // --- Cell statistics ---
  final averageCellVoltage = u16le(data, 58 + cellOffset) * kVoltageScale;
  final deltaCellVoltage = u16le(data, 60 + cellOffset) * kVoltageScale;
  final maxVoltageCellNumber = data[62 + cellOffset];
  final minVoltageCellNumber = data[63 + cellOffset];

  // --- Cell resistances (offset 64 + cellOffset, 2 bytes each) ---
  final cellResistances = <double>[];
  for (int i = 0; i < cellCount; i++) {
    cellResistances.add(u16le(data, 64 + cellOffset + i * 2) * kResistanceScale);
  }

  // --- Main electrical fields (use mainOffset) ---
  final totalVoltage = u32le(data, 118 + mainOffset) * kVoltageScale;
  final current = i32le(data, 126 + mainOffset) * kCurrentScale;
  final power = totalVoltage * current;
  final temperature1 = i16le(data, 130 + mainOffset) * kTemperatureScale;
  final temperature2 = i16le(data, 132 + mainOffset) * kTemperatureScale;

  // MOS temperature (JK02_24S only at 134 + mainOffset)
  double mosTemperature = 0.0;
  if (protocol == JkProtocol.jk02_24s) {
    mosTemperature = i16le(data, 134 + mainOffset) * kTemperatureScale;
  }

  // --- Error bitmask ---
  int errors;
  if (protocol == JkProtocol.jk02_32s) {
    errors = u32le(data, 134 + mainOffset);
  } else {
    errors = u16le(data, 136 + mainOffset);
  }

  // --- Balancer and SOC ---
  final balanceCurrent = i16le(data, 138 + mainOffset) * kCurrentScale;
  final balancerAction = data[140 + mainOffset];
  final soc = data[141 + mainOffset];
  final capacityRemaining = u32le(data, 142 + mainOffset) * kCapacityScale;
  final fullCapacity = u32le(data, 146 + mainOffset) * kCapacityScale;
  final cycleCount = u32le(data, 150 + mainOffset);
  final totalCycleCapacity = u32le(data, 154 + mainOffset) * kCapacityScale;
  final soh = data[158 + mainOffset];
  final totalRuntime = u32le(data, 162 + mainOffset);

  // --- MOSFET and operational states ---
  final chargingEnabled = data[166 + mainOffset] != 0;
  final dischargingEnabled = data[167 + mainOffset] != 0;
  final prechargeEnabled = data[168 + mainOffset] != 0;
  final balancerWorking = data[169 + mainOffset] != 0;
  final heatingEnabled = data[183 + mainOffset] != 0;

  return JkCellStatus(
    cellVoltages: cellVoltages,
    cellResistances: cellResistances,
    enabledCellCount: enabledCellCount,
    averageCellVoltage: averageCellVoltage,
    deltaCellVoltage: deltaCellVoltage,
    maxVoltageCellNumber: maxVoltageCellNumber,
    minVoltageCellNumber: minVoltageCellNumber,
    totalVoltage: totalVoltage,
    current: current,
    power: power,
    temperature1: temperature1,
    temperature2: temperature2,
    mosTemperature: mosTemperature,
    errors: errors,
    balanceCurrent: balanceCurrent,
    balancerAction: balancerAction,
    soc: soc,
    capacityRemaining: capacityRemaining,
    fullCapacity: fullCapacity,
    cycleCount: cycleCount,
    totalCycleCapacity: totalCycleCapacity,
    soh: soh,
    totalRuntime: totalRuntime,
    chargingEnabled: chargingEnabled,
    dischargingEnabled: dischargingEnabled,
    prechargeEnabled: prechargeEnabled,
    balancerWorking: balancerWorking,
    heatingEnabled: heatingEnabled,
  );
}
