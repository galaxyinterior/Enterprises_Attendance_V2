import 'package:flutter_tts/flutter_tts.dart';

class VoiceAnnouncementsService {
  static final VoiceAnnouncementsService _instance = VoiceAnnouncementsService._internal();
  factory VoiceAnnouncementsService() => _instance;
  VoiceAnnouncementsService._internal();

  late FlutterTts _flutterTts;
  bool _isInitialized = false;
  String _currentLanguage = "en-IN";

  Future<void> initialize() async {
    if (_isInitialized) return;
    _flutterTts = FlutterTts();

    await _flutterTts.setLanguage(_currentLanguage);
    await _flutterTts.setVolume(1.0); // Maximum volume for clarity
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5); // Clear, natural speed
    await _flutterTts.awaitSpeakCompletion(true);
    _isInitialized = true;
  }

  Future<void> setLanguage(String langCode) async {
    await initialize();
    _currentLanguage = langCode;
    try {
      await _flutterTts.setLanguage(langCode);
    } catch (_) {}
  }

  String get currentLanguage => _currentLanguage;

  // Speak personalized check-in greeting
  Future<void> speakCheckInGreeting(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);

    String message;
    switch (_currentLanguage) {
      case "hi-IN":
        message = "$employeeName जी, नमस्कार। आपकी हाज़िरी सफलतापूर्वक दर्ज हो गई है।";
        break;
      case "mr-IN":
        message = "$employeeName जी, नमस्कार. तुमची उपस्थिती यशस्वीरित्या नोंदवली गेली आहे.";
        break;
      case "gu-IN":
        message = "$employeeName જી, નમસ્તે. તમારી હાજરી સફળતાપૂર્વક નોંધાઈ ગઈ છે.";
        break;
      case "bn-IN":
        message = "$employeeName জি, নমস্কার। আপনার উপস্থিতি সফলভাবে নথিভুক্ত হয়েছে।";
        break;
      case "ta-IN":
        message = "$employeeName, வணக்கம். உங்கள் வருகை பதிவாகியுள்ளது.";
        break;
      case "te-IN":
        message = "$employeeName, నమస్కారం. మీ హాజరు విజయవంతంగా నమోదైంది.";
        break;
      case "kn-IN":
        message = "$employeeName, ನಮಸ್ಕಾರ. ನಿಮ್ಮ ಹಾಜರಾತಿ ಯಶಸ್ವಿಯಾಗಿ ದಾಖಲಾಗಿದೆ.";
        break;
      default:
        message = "$employeeName, Good Morning. Your attendance has been marked successfully.";
    }
    await _flutterTts.speak(message);
  }

  // Speak personalized checkout greeting
  Future<void> speakCheckOutGreeting(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);

    String message;
    switch (_currentLanguage) {
      case "hi-IN":
        message = "$employeeName जी, धन्यवाद। आपका चेक-आउट दर्ज हो गया है।";
        break;
      case "mr-IN":
        message = "$employeeName जी, धन्यवाद. तुमचा चेक-आऊट नोंदवला गेला आहे.";
        break;
      case "gu-IN":
        message = "$employeeName જી, આભાર. તમારું ચેક-આઉટ નોંધાઈ ગયું છે.";
        break;
      case "bn-IN":
        message = "$employeeName জি, ধন্যবাদ। আপনার চেক-আউট সম্পন্ন হয়েছে।";
        break;
      case "ta-IN":
        message = "$employeeName, நன்றி. உங்கள் வெளியேற்றம் பதிவாகியுள்ளது.";
        break;
      case "te-IN":
        message = "$employeeName, ధన్యవాదాలు. మీ చెక్-అవుట్ నమోదైంది.";
        break;
      case "kn-IN":
        message = "$employeeName, ಧನ್ಯವಾದಗಳು. ನಿಮ್ಮ ಚೆಕ್-ಔಟ್ ದಾಖಲಾಗಿದೆ.";
        break;
      default:
        message = "$employeeName, Thank you. Your checkout has been recorded.";
    }
    await _flutterTts.speak(message);
  }

  // Speak late attendance alert
  Future<void> speakLateGreeting(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);

    String message;
    switch (_currentLanguage) {
      case "hi-IN":
        message = "$employeeName जी, हाज़िरी दर्ज हो गई है। आप आज लेट हैं।";
        break;
      case "mr-IN":
        message = "$employeeName जी, उपस्थिती नोंदवली गेली आहे. तुम्ही आज उशिरा आला आहात.";
        break;
      case "gu-IN":
        message = "$employeeName જી, હાજરી નોંધાઈ ગઈ છે. તમે આજે મોડા આવ્યા છો.";
        break;
      case "bn-IN":
        message = "$employeeName জি, উপস্থিতি নথিভুক্ত হয়েছে। আপনি আজ দেরিতে এসেছেন।";
        break;
      case "ta-IN":
        message = "$employeeName, வருகை பதிவானது. இன்று தாமதமாக வந்துள்ளீர்கள்.";
        break;
      case "te-IN":
        message = "$employeeName, హాజరు నమోదైంది. మీరు ఈరోజు ఆలస్యంగా వచ్చారు.";
        break;
      case "kn-IN":
        message = "$employeeName, ಹಾಜರಾತಿ ದಾಖಲಾಗಿದೆ. ನೀವು ಇಂದು ತಡವಾಗಿ ಬಂದಿದ್ದೀರಿ.";
        break;
      default:
        message = "$employeeName, Attendance marked. You are late today.";
    }
    await _flutterTts.speak(message);
  }

  // Speak Blink Eyes Liveness Prompt
  Future<void> speakBlinkPrompt() async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);

    String message;
    switch (_currentLanguage) {
      case "hi-IN":
        message = "कृपया अपनी पलकें झपकाएं।";
        break;
      case "mr-IN":
        message = "कृपया तुमचे डोळे मिचकावा.";
        break;
      case "gu-IN":
        message = "કૃપા કરીને તમારી આંખો પટપટાવો.";
        break;
      case "bn-IN":
        message = "দয়া করে চোখের পলক ফেলুন।";
        break;
      case "ta-IN":
        message = "தயவுசெய்து உங்கள் கண்களை சிமிட்டுங்கள்.";
        break;
      case "te-IN":
        message = "దయచేసి మీ కళ్ళు మూసి తెరవండి.";
        break;
      case "kn-IN":
        message = "ದಯವಿಟ್ಟು ನಿಮ್ಮ ಕಣ್ಣುಗಳನ್ನು ಮಿಟುಕಿಸಿ.";
        break;
      default:
        message = "Please blink your eyes to verify attendance.";
    }
    await _flutterTts.speak(message);
  }

  Future<void> speakLivenessPrompt() async {
    await speakBlinkPrompt();
  }

  // Speak Already Recorded Alert
  Future<void> speakAlreadyRecorded(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);

    String message;
    switch (_currentLanguage) {
      case "hi-IN":
        message = "$employeeName जी, आपकी आज की हाज़िरी पहले ही दर्ज हो चुकी है।";
        break;
      case "mr-IN":
        message = "$employeeName जी, तुमची आजची उपस्थिती आधीच नोंदवली गेली आहे.";
        break;
      case "gu-IN":
        message = "$employeeName જી, તમારી આજની હાજરી પહેલેથી જ નોંધાઈ ચૂકી છે.";
        break;
      case "bn-IN":
        message = "$employeeName জি, আপনার আজকের উপস্থিতি ইতিমধ্যেই রেকর্ড করা হয়েছে।";
        break;
      case "ta-IN":
        message = "$employeeName, இன்றைய உங்களின் வருகை ஏற்கனவே பதிவாகிவிட்டது.";
        break;
      case "te-IN":
        message = "$employeeName, మీ இன்றைய హాజరు ఇప్పటికే నమోదైంది.";
        break;
      case "kn-IN":
        message = "$employeeName, ನಿಮ್ಮ ಇಂದಿನ ಹಾಜರಾತಿ ಈಗಾಗಲೇ ದಾಖಲಾಗಿದೆ.";
        break;
      default:
        message = "$employeeName, your attendance for today is already recorded.";
    }
    await _flutterTts.speak(message);
  }

  // Speak Late Reason Selection Prompt
  Future<void> speakLateReasonPrompt(String employeeName) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);

    String message;
    switch (_currentLanguage) {
      case "hi-IN":
        message = "$employeeName जी, आप आज लेट हैं। कृपया देर से आने का कारण चुनें।";
        break;
      case "mr-IN":
        message = "$employeeName जी, तुम्ही आज उशिरा आला आहात. कृपया उशीर होण्याचे कारण निवडा.";
        break;
      case "gu-IN":
        message = "$employeeName જી, તમે આજે મોડા આવ્યા છો. કૃપા કરીને મોડા આવવાનું કારણ પસંદ કરો.";
        break;
      case "bn-IN":
        message = "$employeeName জি, আপনি আজ দেরিতে এসেছেন। অনুগ্রহ করে দেরির কারণ বাছুন।";
        break;
      case "ta-IN":
        message = "$employeeName, இன்று தாமதமாக வந்துள்ளீர்கள். தாமதத்திற்கான காரணத்தை தேர்ந்தெடுக்கவும்.";
        break;
      case "te-IN":
        message = "$employeeName, మీరు ఈరోజు ఆలస్యంగా వచ్చారు. ఆలస్యానికి కారణం ఎంచుకోండి.";
        break;
      case "kn-IN":
        message = "$employeeName, ನೀವು ಇಂದು ತಡವಾಗಿ ಬಂದಿದ್ದೀರಿ. ದಯವಿಟ್ಟು ತಡವಾಗಲು ಕಾರಣವನ್ನು ಆಯ್ಕೆಮಾಡಿ.";
        break;
      default:
        message = "$employeeName, you are late today. Please select a reason.";
    }
    await _flutterTts.speak(message);
  }

  // Speak window closed or shift mismatch alert
  Future<void> speakAlert(String alertText) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);
    await _flutterTts.speak(alertText);
  }

  // Speak Emergency Panic Alert
  Future<void> speakEmergencyAlert(String emergencyMessage) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);
    await _flutterTts.setSpeechRate(0.55);
    String prefix = _currentLanguage == "hi-IN" ? "आपातकालीन सूचना!" : "Emergency Announcement!";
    await _flutterTts.speak("$prefix $emergencyMessage");
  }

  // Dedicated speak method for shop broadcast announcements
  Future<void> speakAnnouncement(String announcementMessage, String type) async {
    await initialize();
    await _flutterTts.stop();
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setLanguage(_currentLanguage);
    await _flutterTts.setSpeechRate(0.5);

    String prefix;
    if (_currentLanguage == "hi-IN") {
      if (type == 'emergency') {
        prefix = "आपातकालीन सूचना!";
      } else if (type == 'notice') {
        prefix = "महत्वपूर्ण सूचना!";
      } else {
        prefix = "कृपया ध्यान दें!";
      }
    } else {
      if (type == 'emergency') {
        prefix = "Emergency Announcement!";
      } else if (type == 'notice') {
        prefix = "Important Shop Notice!";
      } else {
        prefix = "Attention please!";
      }
    }

    await _flutterTts.speak("$prefix $announcementMessage");
  }

  void stop() {
    _flutterTts.stop();
  }
}
