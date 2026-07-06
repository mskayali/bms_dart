import 'dart:async';
import 'dart:typed_data';

import 'daly_constants.dart';

/// Assembled Daly BMS response frame.
class DalyFrame {
  const DalyFrame({
    required this.command,
    required this.data,
    required this.checksumValid,
  });

  /// Response command byte (mirrors request command).
  final int command;

  /// The 8 data bytes from the response.
  final Uint8List data;

  /// Whether the checksum validation passed.
  final bool checksumValid;
}

/// Reassembles Daly BMS response frames from BLE notification chunks.
///
/// Daly responses are fixed 13-byte frames starting with `A5 01`.
/// BLE notifications may deliver them as a single chunk or split
/// across multiple notifications.
///
/// Usage:
/// ```dart
/// final assembler = DalyFrameAssembler();
/// assembler.frameStream.listen((frame) {
///   print('Cmd 0x${frame.command.toRadixString(16)}: ${frame.data}');
/// });
/// assembler.addChunk(notificationData);
/// ```
class DalyFrameAssembler {
  DalyFrameAssembler();

  final _controller = StreamController<DalyFrame>.broadcast();
  final List<int> _buffer = [];

  /// Stream of successfully assembled Daly frames.
  Stream<DalyFrame> get frameStream => _controller.stream;

  /// Feed a BLE notification chunk into the assembler.
  void addChunk(Uint8List chunk) {
    _buffer.addAll(chunk);
    _extractFrames();
  }

  /// Try to extract complete 13-byte frames from the buffer.
  void _extractFrames() {
    while (_buffer.length >= kDalyFrameSize) {
      // Search for A5 header
      final headerIdx = _findHeader();
      if (headerIdx < 0) {
        // No header found — discard buffer
        _buffer.clear();
        return;
      }

      // Discard bytes before header
      if (headerIdx > 0) {
        _buffer.removeRange(0, headerIdx);
      }

      // Need at least 13 bytes from header
      if (_buffer.length < kDalyFrameSize) return;

      // Extract frame
      final frameBytes = Uint8List.fromList(
        _buffer.sublist(0, kDalyFrameSize),
      );

      // Validate checksum
      int sum = 0;
      for (int i = 0; i < kDalyFrameSize - 1; i++) {
        sum += frameBytes[i];
      }
      final checksumValid = (sum & 0xFF) == frameBytes[kDalyFrameSize - 1];

      final command = frameBytes[2];
      final data = Uint8List.fromList(frameBytes.sublist(4, 12));

      _controller.add(DalyFrame(
        command: command,
        data: data,
        checksumValid: checksumValid,
      ));

      // Remove consumed frame from buffer
      _buffer.removeRange(0, kDalyFrameSize);
    }
  }

  /// Find index of `0xA5` header byte in buffer.
  int _findHeader() {
    for (int i = 0; i < _buffer.length; i++) {
      if (_buffer[i] == kDalyHeader) {
        // Verify second byte is BMS address if available
        if (i + 1 < _buffer.length && _buffer[i + 1] != kDalyBmsAddress) {
          continue;
        }
        return i;
      }
    }
    return -1;
  }

  /// Clear internal buffer.
  void reset() {
    _buffer.clear();
  }

  /// Current buffer length.
  int get bufferLength => _buffer.length;

  /// Release resources.
  void dispose() {
    _controller.close();
    _buffer.clear();
  }
}
