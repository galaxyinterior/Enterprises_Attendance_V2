import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_app/core/services/face_recognition_service.dart';
import 'package:attendance_app/models/employee_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Face Verification Diagnostic & Pipeline Tests', () {
    final faceService = FaceRecognitionService();

    test('1. Cosine Similarity - Same Vector matches 1.0', () {
      final vecA = List.generate(128, (i) => sin(i.toDouble()));
      // Normalize vecA
      final normA = sqrt(vecA.fold(0.0, (sum, x) => sum + x * x));
      final normVecA = vecA.map((x) => x / normA).toList();

      final score = faceService.calculateCosineSimilarity(normVecA, normVecA);
      expect(score, closeTo(1.0, 0.0001));
    });

    test('2. Cosine Similarity - Similar vectors give high similarity', () {
      final vecA = List.generate(128, (i) => sin(i.toDouble()));
      final normA = sqrt(vecA.fold(0.0, (sum, x) => sum + x * x));
      final normVecA = vecA.map((x) => x / normA).toList();

      // Slightly perturbed vector for same person
      final vecB = List.generate(128, (i) => sin(i.toDouble()) + 0.05 * cos(i.toDouble()));
      final normB = sqrt(vecB.fold(0.0, (sum, x) => sum + x * x));
      final normVecB = vecB.map((x) => x / normB).toList();

      // Completely different vector for different person
      final vecC = List.generate(128, (i) => cos(i * 3.0));
      final normC = sqrt(vecC.fold(0.0, (sum, x) => sum + x * x));
      final normVecC = vecC.map((x) => x / normC).toList();

      final samePersonScore = faceService.calculateCosineSimilarity(normVecA, normVecB);
      final diffPersonScore = faceService.calculateCosineSimilarity(normVecA, normVecC);

      expect(samePersonScore, greaterThan(0.85));
      expect(diffPersonScore, lessThan(0.40));
      expect(samePersonScore, greaterThan(diffPersonScore));

      final testRes = faceService.runSelfDiagnosticTest(
        sampleA: normVecA,
        sampleB: normVecB,
        differentPersonSample: normVecC,
      );
      expect(testRes['isPass'], isTrue);
    });

    test('3. Match Face - Correct Employee Selection', () {
      final vecA = List.generate(128, (i) => sin(i.toDouble()));
      final normA = sqrt(vecA.fold(0.0, (sum, x) => sum + x * x));
      final normVecA = vecA.map((x) => x / normA).toList();

      final vecB = List.generate(128, (i) => sin(i.toDouble()) + 0.02);
      final normB = sqrt(vecB.fold(0.0, (sum, x) => sum + x * x));
      final normVecB = vecB.map((x) => x / normB).toList();

      final enrolledList = [
        {
          'employeeId': 'EMP-101',
          'fullName': 'Ramesh Kumar',
          'faceEmbedding': normVecB,
        },
        {
          'employeeId': 'EMP-102',
          'fullName': 'Suresh Sharma',
          'faceEmbedding': List.generate(128, (i) => cos(i.toDouble())),
        }
      ];

      final match = faceService.matchFace(
        targetEmbedding: normVecA,
        enrolledEmployees: enrolledList,
        threshold: 0.65,
      );

      expect(match, isNotNull);
      expect(match!['employeeId'], equals('EMP-101'));
      expect(match['employeeName'], equals('Ramesh Kumar'));
      expect(match['confidence'], greaterThan(0.65));
    });

    test('4. Employee Model Serialization / Deserialization', () {
      final vec = List.generate(128, (i) => i.toDouble() / 128.0);
      final emp = EmployeeModel(
        employeeId: 'EMP-999',
        businessId: 'BIZ-01',
        employeeCode: 'EMP-999',
        fullName: 'Test Employee',
        phone: '9876543210',
        department: 'Engineering',
        designation: 'Lead',
        assignedShiftId: 'Morning Shift',
        joiningDate: DateTime(2026, 1, 1),
        monthlySalary: 50000,
        faceEnrollmentStatus: true,
        faceEmbedding: vec,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = emp.toMap();
      final restored = EmployeeModel.fromMap(map);

      expect(restored.employeeId, equals('EMP-999'));
      expect(restored.faceEmbedding, isNotNull);
      expect(restored.faceEmbedding!.length, equals(128));
      expect(restored.faceEmbedding!.first, closeTo(0.0, 0.001));
    });

    test('5. Multi-Angle Embedding Synthesis', () {
      final vecCenter = List.generate(128, (i) => sin(i.toDouble()));
      final vecLeft = List.generate(128, (i) => sin(i.toDouble()) + 0.01 * cos(i.toDouble()));
      final vecRight = List.generate(128, (i) => sin(i.toDouble()) - 0.01 * cos(i.toDouble()));

      final synthesized = faceService.synthesizeMultiAngleEmbedding([vecCenter, vecLeft, vecRight]);

      expect(synthesized, isNotNull);
      expect(synthesized!.length, equals(128));

      // Calculate L2 norm of synthesized vector
      final norm = sqrt(synthesized.fold(0.0, (sum, x) => sum + x * x));
      expect(norm, closeTo(1.0, 0.0001));

      // Compare similarity between synthesized embedding and center embedding
      final normCenter = sqrt(vecCenter.fold(0.0, (sum, x) => sum + x * x));
      final normVecCenter = vecCenter.map((x) => x / normCenter).toList();
      final score = faceService.calculateCosineSimilarity(synthesized, normVecCenter);
      expect(score, greaterThan(0.95));
    });
  });
}
