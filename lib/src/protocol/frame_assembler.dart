import 'dart:async';
import 'dart:typed_data';

import 'checksum.dart';
import 'constants.dart';

/// Assembled frame result from [FrameAssembler].
class AssembledFrame {
  const AssembledFrame({
    required this.frameType,
    required this.data,
    required this.crcValid,
  });

  /// Frame type byte at offset 4 (e.g. [kFrameTypeCellInfo]).
  final int frameType;

  /// Complete reassembled frame data.
  final Uint8List data;

  /// Whether the CRC check passed.
  final bool crcValid;
}

/// Reassembles fragmented BLE notification chunks into complete JK-BMS
/// response frames.
///
/// BLE notifications arrive in small chunks (typically 20 bytes each).
/// This class buffers incoming chunks, detects the `55 AA EB 90` preamble,
/// validates the CRC, and emits complete [AssembledFrame] objects.
///
/// Usage:
/// ```dart
/// final assembler = FrameAssembler();
/// assembler.frameStream.listen((frame) {
///   print('Got frame type: 0x${frame.frameType.toRadixString(16)}');
/// });
///
/// // Feed notification chunks:
/// assembler.addChunk(notificationData);
/// ```
class FrameAssembler {
  FrameAssembler();

  final _controller = StreamController<AssembledFrame>.broadcast();
  final _rawController = StreamController<_RawChunkEvent>.broadcast();

  /// Internal buffer for accumulating notification chunks.
  final List<int> _buffer = [];

  /// Stream of successfully assembled frames.
  Stream<AssembledFrame> get frameStream => _controller.stream;

  /// Stream of raw chunk events (for debug logging).
  Stream<_RawChunkEvent> get rawChunkStream => _rawController.stream;

  /// Feed a BLE notification chunk into the assembler.
  ///
  /// When the preamble `55 AA EB 90` is detected at the start of [chunk],
  /// any existing buffer is discarded and a new frame accumulation begins.
  /// Once the buffer reaches [kMinResponseSize] bytes, the CRC is checked
  /// and the frame is emitted.
  ///
  /// If the CRC check fails but a preamble is found inside the buffer,
  /// the buffer is trimmed to that position and CRC is re-checked. This
  /// pattern comes from batmon-ha (`_notification_handler`) and handles
  /// corrupted leading bytes or junk data floods (e.g., JK-PB `AT\r\n`
  /// flood, batmon-ha issue #370).
  void addChunk(Uint8List chunk) {
    // Emit raw chunk for debug logging
    _rawController.add(_RawChunkEvent(
      data: Uint8List.fromList(chunk),
      bufferLengthBefore: _buffer.length,
    ));

    // Detect response preamble — start new frame
    if (_startsWithPreamble(chunk)) {
      _buffer.clear();
    }

    _buffer.addAll(chunk);

    // Check if we have enough data
    if (_buffer.length >= kMinResponseSize) {
      var frame = Uint8List.fromList(_buffer);
      var crcValid = validateResponseCrc(frame);

      // batmon-ha pattern: if CRC fails, look for preamble inside buffer
      // and retry from that position (handles corrupted leading bytes).
      if (!crcValid) {
        final idx = _findPreambleInBuffer(1); // skip position 0
        if (idx > 0 && _buffer.length - idx >= kMinResponseSize) {
          _buffer.removeRange(0, idx);
          frame = Uint8List.fromList(_buffer);
          crcValid = validateResponseCrc(frame);
        }
      }

      final frameType = frame[4];

      _controller.add(AssembledFrame(
        frameType: frameType,
        data: frame,
        crcValid: crcValid,
      ));

      _buffer.clear();
    }
  }

  /// Clears the internal buffer without emitting.
  void reset() {
    _buffer.clear();
  }

  /// Current buffer length (useful for progress monitoring).
  int get bufferLength => _buffer.length;

  /// Release resources.
  void dispose() {
    _controller.close();
    _rawController.close();
    _buffer.clear();
  }

  /// Checks if [data] starts with the response preamble `55 AA EB 90`.
  bool _startsWithPreamble(Uint8List data) {
    if (data.length < kResponseHeader.length) return false;
    for (int i = 0; i < kResponseHeader.length; i++) {
      if (data[i] != kResponseHeader[i]) return false;
    }
    return true;
  }

  /// Searches for the response preamble `55 AA EB 90` in the buffer,
  /// starting from [startIndex]. Returns the index or -1 if not found.
  ///
  /// Used for the batmon-ha mid-buffer preamble recovery pattern.
  int _findPreambleInBuffer(int startIndex) {
    final headerLen = kResponseHeader.length;
    for (int i = startIndex; i <= _buffer.length - headerLen; i++) {
      bool match = true;
      for (int j = 0; j < headerLen; j++) {
        if (_buffer[i + j] != kResponseHeader[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}

/// Internal event for raw chunk logging.
class _RawChunkEvent {
  const _RawChunkEvent({
    required this.data,
    required this.bufferLengthBefore,
  });

  final Uint8List data;
  final int bufferLengthBefore;
}
