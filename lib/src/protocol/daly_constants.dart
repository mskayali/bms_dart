import 'dart:typed_data';

/// Daly BMS UART-over-BLE protocol constants.
///
/// Frame structure (13 bytes fixed):
/// ```
/// [Header] [Address] [Command] [Length] [Data×8] [Checksum]
///  0xA5     0x40/01   0x90..    0x08     8 bytes   sum&0xFF
/// ```

// ---------------------------------------------------------------------------
// GATT Service / Characteristic (BLE-UART bridge)
// ---------------------------------------------------------------------------

/// Daly BMS BLE service UUID.
const String kDalyServiceUuid = '0000FFF0-0000-1000-8000-00805F9B34FB';

/// Daly BMS notify characteristic (BMS → Host).
const String kDalyNotifyCharUuid = '0000FFF1-0000-1000-8000-00805F9B34FB';

/// Daly BMS write characteristic (Host → BMS).
const String kDalyWriteCharUuid = '0000FFF2-0000-1000-8000-00805F9B34FB';

// ---------------------------------------------------------------------------
// Frame Layout
// ---------------------------------------------------------------------------

/// Frame header byte.
const int kDalyHeader = 0xA5;

/// Host → BMS address byte for BLE (address=8).
/// USB/RS485 uses 0x40 (address=4).
const int kDalyHostAddressBle = 0x80;

/// Host → BMS address byte for USB/RS485 (address=4).
const int kDalyHostAddressUsb = 0x40;

/// BMS → Host address byte.
const int kDalyBmsAddress = 0x01;

/// Fixed data length in every Daly frame.
const int kDalyDataLength = 0x08;

/// Total frame size (header + address + command + length + 8 data + checksum).
const int kDalyFrameSize = 13;

// ---------------------------------------------------------------------------
// Commands (Host → BMS)
// ---------------------------------------------------------------------------

/// Pack voltage, current, SOC.
const int kDalyCmdSoc = 0x90;

/// Max/min cell voltage.
const int kDalyCmdMinMaxVoltage = 0x91;

/// Max/min temperature.
const int kDalyCmdMinMaxTemp = 0x92;

/// Charge/discharge MOS status, cycle count.
const int kDalyCmdMosStatus = 0x93;

/// Status info (cell count, NTC count).
const int kDalyCmdStatusInfo = 0x94;

/// Individual cell voltages (multi-frame response).
const int kDalyCmdCellVoltages = 0x95;

/// Individual cell temperatures.
const int kDalyCmdCellTemps = 0x96;

/// Cell balancing state.
const int kDalyCmdBalancing = 0x97;

/// Failure/alarm status.
const int kDalyCmdFailure = 0x98;

// ---------------------------------------------------------------------------
// Extended Commands (Device Info / Configuration)
// ---------------------------------------------------------------------------

/// Rated parameters (nominal voltage, capacity, etc.).
const int kDalyCmdRatedParams = 0x50;

/// Battery details (production date, etc.).
const int kDalyCmdBatteryDetails = 0x53;

/// Battery code / serial number (ASCII string, multi-frame).
const int kDalyCmdBatteryCode = 0x57;

// ---------------------------------------------------------------------------
// Scaling
// ---------------------------------------------------------------------------

/// Voltage scale: raw × 0.1 V.
const double kDalyVoltageScale = 0.1;

/// Current offset (raw - 30000) then × 0.1 A.
const int kDalyCurrentOffset = 30000;

/// Current scale: (raw - offset) × 0.1 A.
const double kDalyCurrentScale = 0.1;

/// SOC scale: raw × 0.1 %.
const double kDalySocScale = 0.1;

/// Temperature offset: raw - 40 °C.
const int kDalyTempOffset = 40;

/// Cell voltage scale: raw × 0.001 V (millivolts).
const double kDalyCellVoltageScale = 0.001;

// ---------------------------------------------------------------------------
// Response preamble
// ---------------------------------------------------------------------------

/// Expected response preamble: A5 01.
final Uint8List kDalyResponseHeader = Uint8List.fromList([0xA5, 0x01]);
