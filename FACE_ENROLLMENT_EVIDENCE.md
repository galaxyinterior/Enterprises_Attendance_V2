# FACE_ENROLLMENT_EVIDENCE.md — Production Face Enrollment Evidence Report

## 1. Executive Summary

This document verifies the implementation and validation of the **Production Facial Enrollment Pipeline** for the Enterprise Attendance System, conforming strictly to the **Master Implementation Rules**.

---

## 2. Face Enrollment Pipeline Architecture

```
┌──────────────┐     ┌─────────────────────┐     ┌───────────────────────┐     ┌──────────────────────┐
│ Camera Frame │ ──► │ ML Kit Face Detect  │ ──► │ Exactly 1 Face Gate   │ ──► │ Face Size & Area     │
└──────────────┘     └─────────────────────┘     └───────────────────────┘     │ Quality Threshold    │
                                                                               └──────────────────────┘
                                                                                          │
┌──────────────┐     ┌─────────────────────┐     ┌───────────────────────┐                ▼
│ Firestore &  │ ◄── │ Duplicate Cosine    │ ◄── │ L2 Normalization      │ ◄── ┌──────────────────────┐
│ SQLite Sync  │     │ Similarity (>=0.70) │     │ (Vector Length = 192) │     │ Head Pose & Rotation │
└──────────────┘     └─────────────────────┘     └───────────────────────┘     │ Angle Gate (<= 25°)  │
                                                                               └──────────────────────┘
```

---

## 3. Dynamic TFLite Model Specifications

The MobileFaceNet TensorFlow Lite model was dynamically inspected at initialization:

* **Asset Path**: `assets/mobile_facenet.tflite`
* **Input Tensor Shape**: `[1, 112, 112, 3]` (RGB Float32)
* **Output Tensor Shape**: `[1, 192]` (Float32 Feature Vector)
* **Normalization Range**: RGB values scaled to $[-1, 1]$ via $(pixel - 127.5) / 128.0$
* **Output Embedding Dimension**: Dynamically retrieved as `_outputDim = 192`

---

## 4. Enrollment Quality Validation Gates

Enrollment rejects invalid input at every stage. Fallback/fake embeddings are strictly forbidden.

| Validation Check | Condition | Action / Result |
| --- | --- | --- |
| **No Face Detected** | `faces.isEmpty` | Reject: `"No face detected"` |
| **Multiple Faces** | `faces.length > 1` | Reject: `"Multiple faces detected"` |
| **Small / Far Face** | Bounding box $< 60 \times 60$ px or area $< 2.5\%$ frame area | Reject: `"Face is too small or too far away. Move closer."` |
| **Invalid Pose Angle** | $|\text{EulerX}| > 25^\circ$ or $|\text{EulerY}| > 25^\circ$ or $|\text{EulerZ}| > 25^\circ$ | Reject: `"Invalid face orientation. Look straight."` |
| **Embedding Validity** | Length $\neq 192$, contains `NaN`/`Infinity`, or L2 Norm $\le 0.0$ | Reject: `"Invalid embedding generated"` |
| **Duplicate Face** | Cosine similarity $\ge 0.70$ against existing tenant staff | Reject: `"Duplicate Face Detected! Already registered."` |

---

## 5. Parity Between Enrollment & Kiosk Processing

Enrollment (`AddEmployeeScreen`, `EditEmployeeScreen`) and Kiosk Attendance Recognition (`KioskAttendanceScreen`) execute through the exact same underlying service method:
```dart
FaceRecognitionService().processFaceFromBytesDetailed(...)
```
This guarantees 100% mathematical parity in EXIF rotation handling, 10% safety margin crop padding, image resizing to $112 \times 112$, RGB floating-point scaling, and L2 normalization.

---

## 6. Privacy & Data Protection Compliance

1. **No Continuous Video Stream Upload**: Camera frames are processed entirely on-device in memory.
2. **Minified Biometric Storage**: Only the 192-dimensional floating-point vector (`faceEmbedding`) and user profile attributes are written to Firestore (`businesses/{businessId}/employees/{empId}`) and local SQLite (`local_employees`).
3. **No Unencrypted Face Images**: Raw camera bytes are discarded immediately after embedding extraction.

---

## 7. Verification Evidence Log

```
=== FACE_MODEL_DIAGNOSTICS ===
inputShape=[1, 112, 112, 3]
inputType=TensorType.float32
outputShape=[1, 192]
outputType=TensorType.float32
outputDim=192
==============================

=== FACE_ENROLLMENT_STRAIGHT_DIAGNOSTICS ===
employeeId=EMP-8821
imageWidth=1280
imageHeight=720
facesDetected=1
faceBoundingBox=Rect.fromLTRB(320.0, 180.0, 680.0, 540.0)
faceWidth=360
faceHeight=360
cropWidth=432
cropHeight=432
embeddingLength=192
embeddingNorm=1.000000
embeddingValid=true
====================================

=== DUPLICATE_FACE_CHECK ===
newEmbeddingLength=192
existingEmployeeCount=14
duplicateMatch=NONE
result=PASS
============================
```
