/// Parsed settings from a JK-BMS settings frame (frame type `0x01`).
///
/// Settings frames contain the BMS configuration: cell count, capacity,
/// protection thresholds, and current limits. batmon-ha uses this frame
/// to determine the actual number of cells and the configured capacity,
/// which may differ from the cell-info frame's capacity field.
///
/// Reference: batmon-ha `bmslib/models/jikong.py` — `_decode_msg` for
/// frame type `0x01`, and `_decode_sample` for `num_cells` / capacity usage.
class JkSettings {
  const JkSettings({
    required this.numCells,
    required this.nominalCapacity,
    required this.cellOvp,
    required this.cellOvpRecovery,
    required this.cellUvp,
    required this.cellUvpRecovery,
    required this.balanceStartVoltage,
    required this.balanceDelta,
    required this.maxChargeCurrent,
    required this.maxDischargeCurrent,
    required this.chargeOtp,
    required this.chargeUtp,
    required this.dischargeOtp,
    required this.dischargeUtp,
    required this.batteryType,
    required this.rawData,
  });

  /// Number of series cells configured.
  /// Read from byte 114 of the settings frame.
  /// This is the authoritative cell count (batmon-ha pattern).
  final int numCells;

  /// Configured nominal capacity in Ah.
  /// Read from bytes 146–149 (u32le) × 0.001 Ah.
  /// batmon-ha uses this value over the cell-info frame's capacity
  /// for SOC precision (#369 fix).
  final double nominalCapacity;

  /// Cell over-voltage protection threshold in V.
  final double cellOvp;

  /// Cell OVP recovery voltage in V.
  final double cellOvpRecovery;

  /// Cell under-voltage protection threshold in V.
  final double cellUvp;

  /// Cell UVP recovery voltage in V.
  final double cellUvpRecovery;

  /// Cell voltage at which balancing starts, in V.
  final double balanceStartVoltage;

  /// Cell voltage delta above which balancing activates, in V.
  final double balanceDelta;

  /// Maximum charge current in A.
  final double maxChargeCurrent;

  /// Maximum discharge current in A.
  final double maxDischargeCurrent;

  /// Charge over-temperature protection in °C.
  final double chargeOtp;

  /// Charge under-temperature protection in °C.
  final double chargeUtp;

  /// Discharge over-temperature protection in °C.
  final double dischargeOtp;

  /// Discharge under-temperature protection in °C.
  final double dischargeUtp;

  /// Battery type code.
  /// `0`: LiFePO4, `1`: Li-ion, `2`: LTO
  final int batteryType;

  /// Raw frame data for advanced analysis.
  final List<int> rawData;

  /// Human-readable battery type name.
  String get batteryTypeName {
    switch (batteryType) {
      case 0:
        return 'LiFePO4';
      case 1:
        return 'Li-ion';
      case 2:
        return 'LTO';
      default:
        return 'Bilinmiyor ($batteryType)';
    }
  }

  @override
  String toString() =>
      'JkSettings(cells=$numCells, capacity=${nominalCapacity}Ah, '
      'type=$batteryTypeName)';
}
