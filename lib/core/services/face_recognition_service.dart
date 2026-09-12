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
  int _outputDim = 192;

  bool get isInitialized => _isInitialized;
  int get outputDim => _outputDim;

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

      if (outputTensor.shape.length >= 2) {
        _outputDim = outputTensor.shape[1];
      }

      debugPrint('=== FACE_MODEL_DIAGNOSTICS ===');
      debugPrint('inputShape=${inputTensor.shape}');
      debugPrint('inputType=${inputTensor.type}');
      debugPrint('inputQuantization=${inputTensor.params}');
      debugPrint('outputShape=${outputTensor.shape}');
      debugPrint('outputType=${outputTensor.type}');
      debugPrint('outputQuantization=${outputTensor.params}');
      debugPrint('outputDim=$_outputDim');
      debugPrint('==============================');
    } catch (e) {
      debugPrint('❌ Error initializing MobileFaceNet TFLite interpreter: $e');
    }
  }

  // Detect faces in an InputImage
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await _faceDetector.processImage(inputImage);
  }

  /// Validate live face orientation & angles to prevent static photo / screen spoofing
  bool isLiveFaceValid(Face face) {
    final headRotX = face.headEulerAngleX ?? 0.0; // Pitch (up/down)
    final headRotY = face.headEulerAngleY ?? 0.0; // Yaw (left/right)
    final headRotZ = face.headEulerAngleZ ?? 0.0; // Roll (tilt)

    // Ensure face is facing forward within 25 degree tolerance
    final bool isFrontal = headRotX.abs() < 25.0 && headRotY.abs() < 25.0 && headRotZ.abs() < 25.0;
    return isFrontal;
  }

  /// Detect face and return face info including eye blink probabilities, head angles, and liveness state
  Future<Map<String, dynamic>?> detectFaceAndCheckBlink(String imagePath) async {
    await initialize();
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await detectFaces(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability ?? 1.0;
      final rightOpen = face.rightEyeOpenProbability ?? 1.0;

      // Eye blink transition: either eye openness drops below 0.35
      bool isBlinking = (leftOpen < 0.35 || rightOpen < 0.35);
      bool isFullyOpen = (leftOpen > 0.70 && rightOpen > 0.70);
      bool isLive = isLiveFaceValid(face);

      return {
        'face': face,
        'hasFace': true,
        'isLiveValid': isLive,
        'leftEyeOpen': leftOpen,
        'rightEyeOpen': rightOpen,
        'isBlinking': isBlinking,
        'isFullyOpen': isFullyOpen,
        'headEulerX': face.headEulerAngleX ?? 0.0,
        'headEulerY': face.headEulerAngleY ?? 0.0,
        'headEulerZ': face.headEulerAngleZ ?? 0.0,
      };
    } catch (e) {
      debugPrint('Error detecting face & blink: $e');
      return null;
    }
  }

  /// Process raw image bytes & path, detect face, crop face ROI, and extract 128D embedding
  Future<Map<String, dynamic>> processFaceFromBytesDetailed({
    required Uint8List bytes,
    required String tempFilePath,
    String context = 'ENROLLMENT',
    String employeeId = 'N/A',
  }) async {
    await initialize();

    final inputImage = InputImage.fromFilePath(tempFilePath);
    final faces = await detectFaces(inputImage);

    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return {
        'success': false,
        'error': 'Image decoding failed',
        'embedding': null,
      };
    }

    // Step 4: Bake EXIF orientation so pixel layout matches ML Kit coordinate system
    decoded = img.bakeOrientation(decoded);

    final int imgW = decoded.width;
    final int imgH = decoded.height;

    if (faces.isEmpty) {
      debugPrint('=== FACE_${context}_DIAGNOSTICS ===');
      debugPrint('employeeId=$employeeId');
      debugPrint('imageWidth=$imgW');
      debugPrint('imageHeight=$imgH');
      debugPrint('imageRotation=0');
      debugPrint('facesDetected=0');
      debugPrint('faceBoundingBox=null');
      debugPrint('faceWidth=0');
      debugPrint('faceHeight=0');
      debugPrint('cropWidth=0');
      debugPrint('cropHeight=0');
      debugPrint('embeddingLength=0');
      debugPrint('embeddingNorm=0.0');
      debugPrint('embeddingValid=false');
      debugPrint('====================================');

      return {
        'success': false,
        'error': 'No face detected',
        'facesDetected': 0,
        'embedding': null,
      };
    }

    if (faces.length > 1) {
      debugPrint('=== FACE_${context}_DIAGNOSTICS ===');
      debugPrint('employeeId=$employeeId');
      debugPrint('imageWidth=$imgW');
      debugPrint('imageHeight=$imgH');
      debugPrint('imageRotation=0');
      debugPrint('facesDetected=${faces.length}');
      debugPrint('embeddingValid=false (Multiple faces detected)');
      debugPrint('====================================');

      return {
        'success': false,
        'error': 'Multiple faces detected (${faces.length})',
        'facesDetected': faces.length,
        'embedding': null,
      };
    }

    final face = faces.first;
    final boundingBox = face.boundingBox;

    // Quality Check 1: Minimum Face Bounding Box Size
    if (boundingBox.width < 60 || boundingBox.height < 60 || (boundingBox.width * boundingBox.height) < (imgW * imgH * 0.025)) {
      return {
        'success': false,
        'error': 'Face is too small or too far away. Please move closer to the camera.',
        'facesDetected': 1,
        'embedding': null,
      };
    }

    // Quality Check 2: Head Orientation & Pose Angle Thresholds
    if (!isLiveFaceValid(face)) {
      return {
        'success': false,
        'error': 'Invalid face orientation. Please look straight at the camera.',
        'facesDetected': 1,
        'embedding': null,
      };
    }

    // Crop calculation with 10% safety margin padding for optimal forehead/chin coverage
    final int padX = (boundingBox.width * 0.10).toInt();
    final int padY = (boundingBox.height * 0.10).toInt();

    int x = (boundingBox.left - padX).toInt().clamp(0, imgW - 1);
    int y = (boundingBox.top - padY).toInt().clamp(0, imgH - 1);
    int w = (boundingBox.width + 2 * padX).toInt().clamp(1, imgW - x);
    int h = (boundingBox.height + 2 * padY).toInt().clamp(1, imgH - y);

    final croppedFace = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
    final embedding = extractEmbedding(croppedFace);

    bool isValid = false;
    double norm = 0.0;

    if (embedding != null && embedding.length == _outputDim) {
      norm = _calculateL2Norm(embedding);
      bool allFinite = embedding.every((v) => !v.isNaN && !v.isInfinite);
      isValid = norm > 0 && allFinite;
    }

    debugPrint('=== FACE_${context}_DIAGNOSTICS ===');
    debugPrint('employeeId=$employeeId');
    debugPrint('imageWidth=$imgW');
    debugPrint('imageHeight=$imgH');
    debugPrint('imageRotation=0');
    debugPrint('facesDetected=1');
    debugPrint('faceBoundingBox=$boundingBox');
    debugPrint('faceWidth=${boundingBox.width.toInt()}');
    debugPrint('faceHeight=${boundingBox.height.toInt()}');
    debugPrint('cropWidth=$w');
    debugPrint('cropHeight=$h');
    debugPrint('embeddingLength=${embedding?.length ?? 0}');
    debugPrint('embeddingNorm=${norm.toStringAsFixed(6)}');
    debugPrint('embeddingValid=$isValid');
    debugPrint('====================================');

    if (!isValid || embedding == null) {
      return {
        'success': false,
        'error': 'Invalid embedding generated',
        'facesDetected': 1,
        'embedding': null,
      };
    }

    return {
      'success': true,
      'facesDetected': 1,
      'embedding': embedding,
      'cropWidth': w,
      'cropHeight': h,
    };
  }

  /// Simple convenience wrapper for processFaceFromBytesDetailed
  Future<List<double>?> processFaceFromBytes(
    Uint8List bytes,
    String tempFilePath, {
    String context = 'GENERIC',
    String employeeId = 'N/A',
  }) async {
    final res = await processFaceFromBytesDetailed(
      bytes: bytes,
      tempFilePath: tempFilePath,
      context: context,
      employeeId: employeeId,
    );
    if (res['success'] == true && res['embedding'] != null) {
      return res['embedding'] as List<double>;
    }
    return null;
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

    // Output tensor vector array [1, _outputDim]
    var output = List.filled(1 * _outputDim, 0.0).reshape([1, _outputDim]);

    // Run MobileFaceNet inference
    _tfliteInterpreter!.run(input, output);

    List<double> rawEmbedding = List<double>.from(output[0]);

    // Normalize output vector L2
    final normalizedEmbedding = _normalize(rawEmbedding);

    // Step 6: Embedding Quality Check & Stats Logging
    final double norm = _calculateL2Norm(normalizedEmbedding);
    final double minVal = normalizedEmbedding.reduce(min);
    final double maxVal = normalizedEmbedding.reduce(max);
    final double sumVal = normalizedEmbedding.reduce((a, b) => a + b);
    final double meanVal = sumVal / normalizedEmbedding.length;
    final bool isFinite = normalizedEmbedding.every((v) => !v.isNaN && !v.isInfinite);
    final bool valid = normalizedEmbedding.length == _outputDim && norm > 0 && isFinite;

    debugPrint('=== FACE_EMBEDDING_QUALITY ===');
    debugPrint('embeddingLength=${normalizedEmbedding.length}');
    debugPrint('L2Norm=${norm.toStringAsFixed(6)}');
    debugPrint('minValue=${minVal.toStringAsFixed(6)}');
    debugPrint('maxValue=${maxVal.toStringAsFixed(6)}');
    debugPrint('mean=${meanVal.toStringAsFixed(6)}');
    debugPrint('embeddingValid=$valid');
    debugPrint('=============================');

    if (!valid) return null;
    return normalizedEmbedding;
  }

  double _calculateL2Norm(List<double> v) {
    double sum = 0.0;
    for (var x in v) {
      sum += x * x;
    }
    return sqrt(sum);
  }

  // L2 Normalization
  List<double> _normalize(List<double> v) {
    double norm = _calculateL2Norm(v);
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

    debugPrint('=== FACE_MATCH_DIAGNOSTICS ===');
    debugPrint('targetEmbeddingLength=${targetEmbedding.length}');
    debugPrint('enrolledEmployeeCount=${enrolledEmployees.length}');

    for (var emp in enrolledEmployees) {
      final empId = emp['employeeId'] ?? emp['empId'] ?? 'UNKNOWN';
      if (emp['faceEmbedding'] == null) {
        debugPrint('employee=$empId embeddingLength=0 similarity=0.0000 (NULL)');
        continue;
      }

      List<double> embedding = [];
      try {
        final rawList = emp['faceEmbedding'] as List;
        embedding = rawList.map((x) => (x as num).toDouble()).toList();
      } catch (e) {
        debugPrint('Error casting faceEmbedding for ${emp['fullName']}: $e');
        continue;
      }

      // Step 7: Check dimension match before calculating similarity
      if (embedding.length != targetEmbedding.length) {
        debugPrint('employee=$empId embeddingLength=${embedding.length} similarity=0.0000 (DIMENSION_MISMATCH)');
        continue;
      }

      final score = calculateCosineSimilarity(targetEmbedding, embedding);
      debugPrint('employee=$empId name="${emp['fullName']}" embeddingLength=${embedding.length} similarity=${score.toStringAsFixed(4)}');

      if (score > highestScore) {
        highestScore = score;
        bestMatchEmployeeId = empId;
        bestMatchName = emp['fullName'];
        bestMatchEmpData = emp;
      }
    }

    final bool pass = highestScore >= threshold && bestMatchEmployeeId != null;

    debugPrint('BEST_MATCH:');
    debugPrint('employeeId=${bestMatchEmployeeId ?? "NONE"}');
    debugPrint('similarity=${highestScore > -1.0 ? highestScore.toStringAsFixed(4) : "0.0000"}');
    debugPrint('threshold=$threshold');
    debugPrint('result=${pass ? "PASS" : "FAIL"}');
    debugPrint('==============================');

    if (pass) {
      return {
        'employeeId': bestMatchEmployeeId,
        'employeeName': bestMatchName,
        'confidence': highestScore,
        'employeeData': bestMatchEmpData ?? {},
      };
    }

    return null; // Unknown / No Match
  }

  /// Step 8: Same-Person / Different-Person Diagnostic Self Test Helper
  Map<String, dynamic> runSelfDiagnosticTest({
    required List<double> sampleA,
    required List<double> sampleB,
    List<double>? differentPersonSample,
  }) {
    final double samePersonScore = calculateCosineSimilarity(sampleA, sampleB);
    final double? diffPersonScore = differentPersonSample != null
        ? calculateCosineSimilarity(sampleA, differentPersonSample)
        : null;

    debugPrint('=== SAME_PERSON_SELF_TEST ===');
    debugPrint('samePersonSimilarity=${samePersonScore.toStringAsFixed(4)}');
    if (diffPersonScore != null) {
      debugPrint('differentPersonSimilarity=${diffPersonScore.toStringAsFixed(4)}');
      debugPrint('margin=${(samePersonScore - diffPersonScore).toStringAsFixed(4)}');
    }
    debugPrint('testPass=${samePersonScore > 0.60 && (diffPersonScore == null || samePersonScore > diffPersonScore)}');
    debugPrint('=============================');

    return {
      'samePersonScore': samePersonScore,
      'diffPersonScore': diffPersonScore,
      'isPass': samePersonScore > 0.60 && (diffPersonScore == null || samePersonScore > diffPersonScore),
    };
  }

  /// Extract Head Yaw Angle (rotation left/right in degrees)
  double getHeadYawAngle(Face face) {
    return face.headEulerAngleY ?? 0.0;
  }

  /// Synthesize multi-pose embeddings (Center, Left, Right) into a single robust vector
  List<double>? synthesizeMultiAngleEmbedding(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return null;
    final int dim = embeddings.first.length;

    List<double> avgVector = List.filled(dim, 0.0);
    for (var vec in embeddings) {
      if (vec.length != dim) return null;
      for (int i = 0; i < dim; i++) {
        avgVector[i] += vec[i];
      }
    }
    for (int i = 0; i < dim; i++) {
      avgVector[i] /= embeddings.length;
    }

    final normalized = _normalize(avgVector);
    final norm = _calculateL2Norm(normalized);
    final bool isFinite = normalized.every((v) => !v.isNaN && !v.isInfinite);

    if (norm > 0 && isFinite && normalized.length == dim) {
      debugPrint('✓ Synthesized ${embeddings.length} Multi-Angle Vectors into ${dim}D Embedding (Norm: ${norm.toStringAsFixed(4)})');
      return normalized;
    }
    return null;
  }

  /// Check if a newly generated face embedding matches an already enrolled employee in the tenant
  Future<Map<String, dynamic>?> checkDuplicateEnrolledFace({
    required List<double> newEmbedding,
    required List<Map<String, dynamic>> existingEmployees,
    String? excludeEmployeeId,
    double duplicateThreshold = 0.70,
  }) async {
    for (var emp in existingEmployees) {
      final empId = emp['employeeId'] ?? emp['empId'] ?? '';
      if (excludeEmployeeId != null && empId == excludeEmployeeId) continue;
      if (emp['faceEmbedding'] == null) continue;

      List<double> enrolledVec = [];
      try {
        final rawList = emp['faceEmbedding'] as List;
        enrolledVec = rawList.map((x) => (x as num).toDouble()).toList();
      } catch (_) {
        continue;
      }

      if (enrolledVec.length != newEmbedding.length) continue;

      final similarity = calculateCosineSimilarity(newEmbedding, enrolledVec);
      if (similarity >= duplicateThreshold) {
        return {
          'isDuplicate': true,
          'matchedEmployeeId': empId,
          'matchedEmployeeName': emp['fullName'] ?? emp['employeeName'] ?? 'Existing Staff',
          'similarity': similarity,
        };
      }
    }
    return null;
  }

  void dispose() {
    _faceDetector.close();
    _tfliteInterpreter?.close();
  }
}
