import 'package:flutter_tts/flutter_tts.dart';

class VoiceAnnouncementsService {
  static final VoiceAnnouncementsService _instance = VoiceAnnouncementsService._internal();
  factory VoiceAnnouncementsService() => _instance;
  VoiceAnnouncementsService._internal();

  late FlutterTts _flutterTts;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _flutterTts = FlutterTts();

    await _flutterTts.setLanguage("en-IN"); // Indian English accent default
    await _flutterTts.setVolume(1.0); // Maximum volume for clarity
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5); // Clear, natural speed
    await _flutterTts.awaitSpeakCompletion(true);
    _isInitialized = true;
  }

  // Speak personalized check-in greeting
  Future<void> speakCheckInGreeting(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    String message = "$employeeName, Good Morning. Your attendance has been marked successfully.";
    await _flutterTts.speak(message);
  }

  // Speak personalized checkout greeting
  Future<void> speakCheckOutGreeting(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    String message = "$employeeName, Thank you. Your checkout has been recorded.";
    await _flutterTts.speak(message);
  }

  // Speak late attendance alert
  Future<void> speakLateGreeting(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    String message = "$employeeName, Attendance marked. You are late today.";
    await _flutterTts.speak(message);
  }

  // Speak Blink Eyes Liveness Prompt
  Future<void> speakBlinkPrompt() async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.speak("Please blink your eyes to verify attendance.");
  }

  Future<void> speakLivenessPrompt() async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.speak("Please blink your eyes to verify attendance.");
  }

  // Speak window closed or shift mismatch alert
  Future<void> speakAlert(String alertText) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.speak(alertText);
  }

  // Speak Emergency Panic Alert
  Future<void> speakEmergencyAlert(String emergencyMessage) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setSpeechRate(0.55);
    await _flutterTts.speak("Emergency Announcement! $emergencyMessage");
  }

  // Dedicated speak method for shop broadcast announcements
  Future<void> speakAnnouncement(String announcementMessage, String type) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setSpeechRate(0.5);

    String prefix = "Attention please!";
    if (type == 'emergency') {
      prefix = "Emergency Announcement!";
    } else if (type == 'notice') {
      prefix = "Important Shop Notice!";
    }

    await _flutterTts.speak("$prefix $announcementMessage");
  }

  void stop() {
    _flutterTts.stop();
  }
}
