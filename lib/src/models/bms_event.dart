import 'dart:typed_data';

import 'cell_status.dart';
import 'device_info.dart';
import 'jk_settings.dart';

/// Base class for events emitted by the BMS manager.
///
/// Use pattern matching to handle specific event types:
/// ```dart
/// manager.eventStream.listen((event) {
///   switch (event) {
///     case BmsCellStatusEvent(:final data):
///       print('SOC: ${data.soc}%');
///     case BmsDeviceInfoEvent(:final data):
///       print('Device: ${data.deviceName}');
///     case BmsRawFrameEvent(:final frameType, :final raw):
///       print('Raw frame 0x${frameType.toRadixString(16)}');
///     case BmsErrorEvent(:final message):
///       print('Error: $message');
///   }
/// });
/// ```
sealed class BmsEvent {
  const BmsEvent({required this.timestamp});

  /// When this event was received.
  final DateTime timestamp;
}

/// Successfully parsed cell/status frame (frame type `0x02`).
class BmsCellStatusEvent extends BmsEvent {
  BmsCellStatusEvent({required this.data})
      : super(timestamp: DateTime.now());

  final JkCellStatus data;

  @override
  String toString() => 'BmsCellStatusEvent($data)';
}

/// Successfully parsed device info frame (frame type `0x03`).
class BmsDeviceInfoEvent extends BmsEvent {
  BmsDeviceInfoEvent({required this.data})
      : super(timestamp: DateTime.now());

  final JkDeviceInfo data;

  @override
  String toString() => 'BmsDeviceInfoEvent($data)';
}

/// Unhandled or raw frame (settings, logbook, or unknown type).
class BmsRawFrameEvent extends BmsEvent {
  BmsRawFrameEvent({required this.frameType, required this.raw})
      : super(timestamp: DateTime.now());

  final int frameType;
  final Uint8List raw;

  @override
  String toString() =>
      'BmsRawFrameEvent(type=0x${frameType.toRadixString(16)}, '
      'len=${raw.length})';
}

/// Successfully parsed settings frame (frame type `0x01`).
///
/// Contains BMS configuration: cell count, capacity, protection thresholds.
/// batmon-ha uses the settings frame as the authoritative source for
/// `num_cells` and `nominal_capacity`.
class BmsSettingsEvent extends BmsEvent {
  BmsSettingsEvent({required this.data})
      : super(timestamp: DateTime.now());

  final JkSettings data;

  @override
  String toString() => 'BmsSettingsEvent($data)';
}

/// Protocol or communication error.
class BmsErrorEvent extends BmsEvent {
  BmsErrorEvent({required this.message, this.details})
      : super(timestamp: DateTime.now());

  final String message;
  final Object? details;

  @override
  String toString() => 'BmsErrorEvent($message)';
}
