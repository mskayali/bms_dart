/// BMS BLE GATT protocol plugin.
///
/// Supports both **JK-BMS** (JK02/JK04) and **Daly BMS** protocols.
/// Protocol is auto-detected on connection.
library jk_bms;

// Protocol — JK02
export 'src/protocol/constants.dart';
export 'src/protocol/checksum.dart';
export 'src/protocol/request_builder.dart';
export 'src/protocol/byte_reader.dart';
export 'src/protocol/frame_assembler.dart';

// Protocol — Daly
export 'src/protocol/daly_constants.dart';
export 'src/protocol/daly_request_builder.dart';
export 'src/protocol/daly_frame_assembler.dart';

// Models
export 'src/models/cell_status.dart';
export 'src/models/device_info.dart';
export 'src/models/jk_settings.dart';
export 'src/models/bms_event.dart';

// Parsers
export 'src/parsers/cell_status_parser.dart';
export 'src/parsers/device_info_parser.dart';
export 'src/parsers/settings_parser.dart';
export 'src/parsers/daly_parser.dart';

// BLE
export 'src/ble/jk_bms_manager.dart';
