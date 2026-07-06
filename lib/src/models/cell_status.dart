/// Parsed cell/status data from a JK-BMS frame type `0x02`.
///
/// All electrical values are already scaled to human-readable units
/// (volts, amps, °C, Ah, etc.).
class JkCellStatus {
  const JkCellStatus({
    required this.cellVoltages,
    required this.cellResistances,
    required this.enabledCellCount,
    required this.averageCellVoltage,
    required this.deltaCellVoltage,
    required this.maxVoltageCellNumber,
    required this.minVoltageCellNumber,
    required this.totalVoltage,
    required this.current,
    required this.power,
    required this.temperature1,
    required this.temperature2,
    required this.mosTemperature,
    required this.errors,
    required this.balanceCurrent,
    required this.balancerAction,
    required this.soc,
    required this.capacityRemaining,
    required this.fullCapacity,
    required this.cycleCount,
    required this.totalCycleCapacity,
    required this.soh,
    this.totalRuntime,
    required this.chargingEnabled,
    required this.dischargingEnabled,
    required this.prechargeEnabled,
    required this.balancerWorking,
    required this.heatingEnabled,
  });

  /// Individual cell voltages in volts. Index 0 = Cell 1.
  final List<double> cellVoltages;

  /// Individual cell resistances in ohms. Index 0 = Cell 1.
  final List<double> cellResistances;

  /// Number of enabled/active cells (from bitmask).
  final int enabledCellCount;

  /// Average cell voltage in volts.
  final double averageCellVoltage;

  /// Voltage delta between max and min cells in volts.
  final double deltaCellVoltage;

  /// 1-based cell number with the highest voltage.
  final int maxVoltageCellNumber;

  /// 1-based cell number with the lowest voltage.
  final int minVoltageCellNumber;

  /// Total pack voltage in volts.
  final double totalVoltage;

  /// Pack current in amps (negative = discharge).
  final double current;

  /// Pack power in watts (computed as totalVoltage × current).
  final double power;

  /// Temperature sensor 1 in °C.
  final double temperature1;

  /// Temperature sensor 2 in °C.
  final double temperature2;

  /// MOSFET temperature in °C.
  final double mosTemperature;

  /// Error bitmask (16-bit for JK02_24S, 32-bit for JK02_32S).
  final int errors;

  /// Balance current in amps.
  final double balanceCurrent;

  /// Balancer action: 0=off, 1=charge balancer, 2=discharge balancer.
  final int balancerAction;

  /// State of charge in percent.
  final int soc;

  /// Remaining capacity in Ah.
  final double capacityRemaining;

  /// Nominal/full capacity in Ah.
  final double fullCapacity;

  /// Number of charge/discharge cycles.
  final int cycleCount;

  /// Total cycle capacity in Ah.
  final double totalCycleCapacity;

  /// State of health in percent.
  final int soh;

  /// Total runtime in seconds (null if unsupported by BMS).
  final int? totalRuntime;

  /// Whether the charging MOSFET is enabled.
  final bool chargingEnabled;

  /// Whether the discharging MOSFET is enabled.
  final bool dischargingEnabled;

  /// Whether precharge is enabled.
  final bool prechargeEnabled;

  /// Whether the balancer is currently working.
  final bool balancerWorking;

  /// Whether heating is enabled.
  final bool heatingEnabled;

  /// Total runtime formatted as "Xd Xh Xm", or "-" if unsupported.
  String get totalRuntimeFormatted {
    if (totalRuntime == null) return '-';
    
    final days = totalRuntime! ~/ 86400;
    final hours = (totalRuntime! % 86400) ~/ 3600;
    final minutes = (totalRuntime! % 3600) ~/ 60;
    return '${days}d ${hours}h ${minutes}m';
  }

  /// Whether any error flags are set.
  bool get hasErrors => errors != 0;

  @override
  String toString() =>
      'JkCellStatus(V=${totalVoltage.toStringAsFixed(2)}V, '
      'I=${current.toStringAsFixed(2)}A, '
      'SOC=$soc%, '
      'cells=${cellVoltages.length})';
}
