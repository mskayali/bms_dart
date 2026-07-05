import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jk_bms/src/protocol/checksum.dart';
import 'package:jk_bms/src/protocol/constants.dart';
import 'package:jk_bms/src/protocol/frame_assembler.dart';

void main() {
  late FrameAssembler assembler;

  setUp(() {
    assembler = FrameAssembler();
  });

  tearDown(() {
    assembler.dispose();
  });

  /// Creates a fake response frame of exactly 300 bytes with the given
  /// [frameType] and a valid CRC at index 299.
  Uint8List _buildFakeFrame(int frameType) {
    final frame = Uint8List(300);
    // Response header
    frame[0] = 0x55;
    frame[1] = 0xAA;
    frame[2] = 0xEB;
    frame[3] = 0x90;
    frame[4] = frameType;
    // Set CRC
    frame[299] = jkChecksum(frame, 299);
    return frame;
  }

  group('FrameAssembler', () {
    test('emits frame when single chunk >= 300 bytes', () async {
      final frame = _buildFakeFrame(kFrameTypeCellInfo);

      final future = assembler.frameStream.first;
      assembler.addChunk(frame);

      final result = await future;
      expect(result.frameType, kFrameTypeCellInfo);
      expect(result.crcValid, true);
      expect(result.data.length, 300);
    });

    test('assembles frame from multiple chunks', () async {
      final frame = _buildFakeFrame(kFrameTypeDeviceInfo);

      // Split into 20-byte chunks (like BLE notifications)
      final chunks = <Uint8List>[];
      for (int i = 0; i < frame.length; i += 20) {
        final end = (i + 20 > frame.length) ? frame.length : i + 20;
        chunks.add(Uint8List.fromList(frame.sublist(i, end)));
      }

      final future = assembler.frameStream.first;
      for (final chunk in chunks) {
        assembler.addChunk(chunk);
      }

      final result = await future;
      expect(result.frameType, kFrameTypeDeviceInfo);
      expect(result.crcValid, true);
    });

    test('resets buffer on new preamble', () async {
      // Start a frame but don't complete it
      final partialFrame = Uint8List(100);
      partialFrame[0] = 0x55;
      partialFrame[1] = 0xAA;
      partialFrame[2] = 0xEB;
      partialFrame[3] = 0x90;
      assembler.addChunk(partialFrame);

      expect(assembler.bufferLength, 100);

      // New frame with preamble should reset
      final fullFrame = _buildFakeFrame(kFrameTypeCellInfo);
      final future = assembler.frameStream.first;
      assembler.addChunk(fullFrame);

      final result = await future;
      expect(result.crcValid, true);
      expect(result.data.length, 300);
    });

    test('detects invalid CRC', () async {
      final frame = Uint8List(300);
      frame[0] = 0x55;
      frame[1] = 0xAA;
      frame[2] = 0xEB;
      frame[3] = 0x90;
      frame[4] = kFrameTypeCellInfo;
      frame[299] = 0xFF; // wrong CRC

      final future = assembler.frameStream.first;
      assembler.addChunk(frame);

      final result = await future;
      expect(result.crcValid, false);
    });

    test('bufferLength tracks accumulated bytes', () {
      expect(assembler.bufferLength, 0);

      assembler.addChunk(Uint8List(50));
      expect(assembler.bufferLength, 50);

      assembler.addChunk(Uint8List(50));
      expect(assembler.bufferLength, 100);
    });

    test('reset clears buffer', () {
      assembler.addChunk(Uint8List(50));
      expect(assembler.bufferLength, 50);

      assembler.reset();
      expect(assembler.bufferLength, 0);
    });
  });

  group('FrameAssembler mid-buffer preamble recovery', () {
    test('recovers valid frame after junk prefix', () async {
      // Build a valid 300-byte frame
      final validFrame = Uint8List(300);
      validFrame[0] = 0x55;
      validFrame[1] = 0xAA;
      validFrame[2] = 0xEB;
      validFrame[3] = 0x90;
      validFrame[4] = kFrameTypeCellInfo;
      validFrame[299] = jkChecksum(validFrame, 299);

      // Prepend 10 bytes of junk, then the valid frame
      final junk = Uint8List(10);
      for (int i = 0; i < 10; i++) {
        junk[i] = 0xAA; // arbitrary junk (not a preamble)
      }

      final frames = <AssembledFrame>[];
      assembler.frameStream.listen(frames.add);

      // Feed junk + valid frame as a single chunk
      final combined = Uint8List(junk.length + validFrame.length);
      combined.setAll(0, junk);
      combined.setAll(junk.length, validFrame);
      assembler.addChunk(combined);

      // Should have recovered the frame via mid-buffer preamble search
      await Future.delayed(Duration.zero);
      expect(frames, hasLength(1));
      expect(frames.first.crcValid, isTrue);
      expect(frames.first.frameType, kFrameTypeCellInfo);
    });

    test('emits invalid CRC when no preamble found in junk', () async {
      // A buffer full of random data with no preamble
      final junkData = Uint8List(300);
      for (int i = 0; i < 300; i++) {
        junkData[i] = i & 0xFF;
      }
      // Make sure it doesn't start with preamble
      junkData[0] = 0x00;

      final frames = <AssembledFrame>[];
      assembler.frameStream.listen(frames.add);

      assembler.addChunk(junkData);

      await Future.delayed(Duration.zero);
      expect(frames, hasLength(1));
      expect(frames.first.crcValid, isFalse);
    });
  });
}
