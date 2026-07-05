/// JK-BMS BLE GATT protocol plugin.
///
/// Provides BLE connectivity to JK-BMS battery management systems,
/// frame assembly, CRC validation, and data parsing for cell/status
/// and device info frames.
library jk_bms;

// Protocol
export 'src/protocol/constants.dart';
export 'src/protocol/checksum.dart';
export 'src/protocol/request_builder.dart';
export 'src/protocol/byte_reader.dart';
export 'src/protocol/frame_assembler.dart';

// Models
export 'src/models/cell_status.dart';
export 'src/models/device_info.dart';
export 'src/models/jk_settings.dart';
export 'src/models/bms_event.dart';

// Parsers
export 'src/parsers/cell_status_parser.dart';
export 'src/parsers/device_info_parser.dart';
export 'src/parsers/settings_parser.dart';

// BLE
export 'src/ble/jk_bms_manager.dart';
