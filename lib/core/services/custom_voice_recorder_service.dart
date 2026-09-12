import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

class CustomVoiceRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isRecording = false;
  bool _isPlayingPreview = false;
  String? _lastRecordedFilePath;
  String? _lastBase64Audio;
  int _recordingDurationSeconds = 0;
  Timer? _timer;

  bool get isRecording => _isRecording;
  bool get isPlayingPreview => _isPlayingPreview;
  String? get lastRecordedFilePath => _lastRecordedFilePath;
  String? get lastBase64Audio => _lastBase64Audio;
  int get recordingDurationSeconds => _recordingDurationSeconds;

  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/custom_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 22050),
          path: path,
        );

        _isRecording = true;
        _recordingDurationSeconds = 0;
        _timer?.cancel();
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          _recordingDurationSeconds++;
        });

        debugPrint('🎙️ Started custom voice recording to: $path');
        return true;
      } else {
        debugPrint('❌ Microphone permission denied');
        return false;
      }
    } catch (e) {
      debugPrint('Error starting audio recording: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> stopRecording() async {
    try {
      _timer?.cancel();
      final path = await _audioRecorder.stop();
      _isRecording = false;

      if (path != null && File(path).existsSync()) {
        final bytes = await File(path).readAsBytes();
        final base64Str = base64Encode(bytes);
        _lastRecordedFilePath = path;
        _lastBase64Audio = base64Str;

        debugPrint('🎙️ Stopped recording. Audio size: ${bytes.length} bytes, base64 len: ${base64Str.length}');
        return {
          'filePath': path,
          'base64Audio': base64Str,
          'durationSeconds': _recordingDurationSeconds,
          'bytesLength': bytes.length,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error stopping audio recording: $e');
      _isRecording = false;
      return null;
    }
  }

  Future<void> playPreview(String filePathOrBase64) async {
    try {
      await _audioPlayer.stop();
      _isPlayingPreview = true;

      _audioPlayer.onPlayerComplete.listen((_) {
        _isPlayingPreview = false;
      });

      if (filePathOrBase64.startsWith('http') || filePathOrBase64.contains('/') || filePathOrBase64.contains('\\')) {
        await _audioPlayer.play(DeviceFileSource(filePathOrBase64));
      } else {
        // Base64 string
        final bytes = base64Decode(filePathOrBase64);
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/preview_audio.m4a');
        await file.writeAsBytes(bytes);
        await _audioPlayer.play(DeviceFileSource(file.path));
      }
    } catch (e) {
      debugPrint('Error playing audio preview: $e');
      _isPlayingPreview = false;
    }
  }

  Future<void> stopPreview() async {
    await _audioPlayer.stop();
    _isPlayingPreview = false;
  }

  void cancelRecording() {
    _timer?.cancel();
    _audioRecorder.stop();
    _isRecording = false;
    _recordingDurationSeconds = 0;
    _lastRecordedFilePath = null;
    _lastBase64Audio = null;
  }

  void dispose() {
    _timer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
  }
}
