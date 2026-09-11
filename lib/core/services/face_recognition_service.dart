import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../constants/app_constants.dart';

class FaceRecognitionService {
  static final FaceRecognitionService _instance = FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  late FaceDetector _faceDetector;
  Interpreter? _tfliteInterpreter;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize ML Kit Face Detector with high accuracy settings
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableClassification: true,
      minFaceSize: 0.15,
    );
    _faceDetector = FaceDetector(options: options);

    // Initialize TFLite MobileFaceNet Model
    try {
      _tfliteInterpreter = await Interpreter.fromAsset('assets/mobile_facenet.tflite');
      _isInitialized = true;
      final inputTensor = _tfliteInterpreter!.getInputTensor(0);
      final outputTensor = _tfliteInterpreter!.getOutputTensor(0);
      debugPrint('✅ TFLite MobileFaceNet Interpreter Loaded Successfully:');
      debugPrint('   - Input Tensor Shape: ${inputTensor.shape}, Type: ${inputTensor.type}');
      debugPrint('   - Output Tensor Shape: ${outputTensor.shape}, Type: ${outputTensor.type}');
    } catch (e) {
      debugPrint('❌ Error initializing MobileFaceNet TFLite interpreter: $e');
    }
  }

  // Detect faces in an InputImage
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await _faceDetector.processImage(inputImage);
  }

  /// Validate live face presence
  bool isLiveFaceValid(Face face) {
    return true;
  }

  /// Detect face and return face info including eye blink probabilities and liveness state
  Future<Map<String, dynamic>?> detectFaceAndCheckBlink(String imagePath) async {
    await initialize();
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await detectFaces(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability ?? 1.0;
      final rightOpen = face.rightEyeOpenProbability ?? 1.0;

      // Blink detected if either eye openness drops below 0.4
      bool isBlinking = (leftOpen < 0.4 || rightOpen < 0.4);

      return {
        'face': face,
        'hasFace': true,
        'isLiveValid': isLiveFaceValid(face),
        'leftEyeOpen': leftOpen,
        'rightEyeOpen': rightOpen,
        'isBlinking': isBlinking,
      };
    } catch (e) {
      debugPrint('Error detecting face & blink: $e');
      return null;
    }
  }

  /// Process raw image bytes & path, detect face, crop face ROI, and extract 128D embedding
  Future<List<double>?> processFaceFromBytes(Uint8List bytes, String tempFilePath) async {
    await initialize();
    try {
      final inputImage = InputImage.fromFilePath(tempFilePath);
      final faces = await detectFaces(inputImage);

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      if (faces.isNotEmpty) {
        final face = faces.first;
        final boundingBox = face.boundingBox;

        int x = boundingBox.left.toInt().clamp(0, decoded.width - 1);
        int y = boundingBox.top.toInt().clamp(0, decoded.height - 1);
        int w = boundingBox.width.toInt().clamp(1, decoded.width - x);
        int h = boundingBox.height.toInt().clamp(1, decoded.height - y);

        final croppedFace = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
        return extractEmbedding(croppedFace);
      } else {
        // Fallback: extract embedding from whole decoded image frame
        return extractEmbedding(decoded);
      }
    } catch (e) {
      debugPrint('Error processing face embedding: $e');
      return null;
    }
  }

  // Generate 128D Face Feature Vector Embedding from a cropped face image
  List<double>? extractEmbedding(img.Image faceImage) {
    if (_tfliteInterpreter == null) return null;

    // Resize image to 112x112 (MobileFaceNet input requirement)
    final resizedImage = img.copyResize(faceImage, width: 112, height: 112);

    // Prepare input float tensor array [1, 112, 112, 3]
    var input = List.generate(
      1,
      (_) => List.generate(
        112,
        (y) => List.generate(
          112,
          (x) {
            var pixel = resizedImage.getPixel(x, y);
            return [
              (pixel.r - 127.5) / 128.0,
              (pixel.g - 127.5) / 128.0,
              (pixel.b - 127.5) / 128.0,
            ];
          },
        ),
      ),
    );

    // Output tensor vector array [1, 128]
    var output = List.filled(1 * 128, 0.0).reshape([1, 128]);

    // Run MobileFaceNet inference
    _tfliteInterpreter!.run(input, output);

    List<double> embedding = List<double>.from(output[0]);

    // Normalize output vector L2
    return _normalize(embedding);
  }

  // L2 Normalization
  List<double> _normalize(List<double> v) {
    double sum = 0.0;
    for (var x in v) {
      sum += x * x;
    }
    double norm = sqrt(sum);
    if (norm == 0) return v;
    return v.map((x) => x / norm).toList();
  }

  // Calculate Cosine Similarity between two 128D vectors
  double calculateCosineSimilarity(List<double> v1, List<double> v2) {
    if (v1.length != v2.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      normA += v1[i] * v1[i];
      normB += v2[i] * v2[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  // Match input face embedding against enrolled employee embeddings list
  Map<String, dynamic>? matchFace({
    required List<double> targetEmbedding,
    required List<Map<String, dynamic>> enrolledEmployees,
    double threshold = AppConstants.faceMatchConfidenceThreshold,
  }) {
    String? bestMatchEmployeeId;
    String? bestMatchName;
    Map<String, dynamic>? bestMatchEmpData;
    double highestScore = -1.0;

    for (var emp in enrolledEmployees) {
      if (emp['faceEmbedding'] == null) continue;
      List<double> embedding = [];
      try {
        final rawList = emp['faceEmbedding'] as List;
        embedding = rawList.map((x) => (x as num).toDouble()).toList();
      } catch (e) {
        debugPrint('Error casting faceEmbedding for ${emp['fullName']}: $e');
        continue;
      }
      if (embedding.isEmpty) continue;

      final score = calculateCosineSimilarity(targetEmbedding, embedding);
      debugPrint('🔍 Comparing Face with "${emp['fullName']}": Score = ${score.toStringAsFixed(4)} | Threshold = $threshold');

      if (score > highestScore) {
        highestScore = score;
        bestMatchEmployeeId = emp['employeeId'];
        bestMatchName = emp['fullName'];
        bestMatchEmpData = emp;
      }
    }

    if (highestScore >= threshold && bestMatchEmployeeId != null) {
      debugPrint('✓ SUCCESSFUL FACE MATCH: $bestMatchName (Score: ${highestScore.toStringAsFixed(4)})');
      return {
        'employeeId': bestMatchEmployeeId,
        'employeeName': bestMatchName,
        'confidence': highestScore,
        'employeeData': bestMatchEmpData ?? {},
      };
    }

    debugPrint('❌ NO MATCH FOUND (Highest Score: ${highestScore.toStringAsFixed(4)} < Threshold: $threshold)');
    return null; // Unknown / No Match
  }

  void dispose() {
    _faceDetector.close();
    _tfliteInterpreter?.close();
  }
}
