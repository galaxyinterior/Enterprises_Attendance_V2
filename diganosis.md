# FACE VERIFICATION — ROOT CAUSE DIAGNOSTIC

## DO NOT RANDOMLY MODIFY THE RECOGNITION LOGIC

You are working on the existing Flutter attendance project.

The kiosk camera detects a person, but face verification/recognition is not reliably matching the enrolled employee.

Your job in this task is NOT to redesign the application and NOT to lower the threshold blindly.

Your first job is to identify the EXACT point where the face verification pipeline fails.

---

## ABSOLUTE RULES

1. DO NOT delete existing features.
2. DO NOT rewrite the entire project.
3. DO NOT replace Firebase, SQLite, TFLite, ML Kit, or the current architecture.
4. DO NOT change the face-match threshold just to make recognition pass.
5. DO NOT introduce fake embeddings.
6. DO NOT introduce fallback/demo employees.
7. DO NOT mark attendance unless a genuine face match occurs.
8. DO NOT claim "fixed" without diagnostic evidence.
9. First instrument the existing pipeline.
10. Only after identifying the root cause, implement the minimum targeted fix.

---

# STEP 1 — VERIFY THE TFLITE MODEL

Inspect:

`assets/mobile_facenet.tflite`

and verify the ACTUAL:

* input tensor shape
* input tensor data type
* input quantization
* output tensor shape
* output tensor data type
* output quantization
* model input dimensions
* model output embedding dimensions

Do NOT assume:

`[1,112,112,3]`

or:

`128D`

unless the actual model proves it.

At application startup print:

```text
FACE_MODEL_DIAGNOSTICS
inputShape=
inputType=
inputQuantization=
outputShape=
outputType=
outputQuantization=
```

If the model is not compatible with the current preprocessing, report it before changing code.

---

# STEP 2 — VERIFY ENROLLMENT PIPELINE

Trace exactly what happens when an employee enrolls a face.

Add diagnostic logging WITHOUT logging sensitive biometric vectors themselves.

Log:

```text
FACE_ENROLLMENT_DIAGNOSTICS

employeeId=
imageWidth=
imageHeight=
imageRotation=
facesDetected=
faceBoundingBox=
faceWidth=
faceHeight=
cropWidth=
cropHeight=
embeddingLength=
embeddingNorm=
embeddingValid=
```

DO NOT print the complete face embedding to logs.

Enrollment must fail if:

* no face is detected
* multiple faces are detected
* crop is invalid
* embedding is null
* embedding length does not equal the actual model output dimension
* embedding norm is zero/invalid

Never generate a fake embedding.

---

# STEP 3 — VERIFY KIOSK PIPELINE

When kiosk scans a face, log:

```text
FACE_KIOSK_DIAGNOSTICS

imageWidth=
imageHeight=
imageRotation=
facesDetected=
faceBoundingBox=
faceWidth=
faceHeight=
cropWidth=
cropHeight=
embeddingLength=
embeddingNorm=
embeddingValid=
```

Again, NEVER print the actual biometric vector.

---

# STEP 4 — VERIFY IMAGE ORIENTATION

This is extremely important.

Inspect the complete pipeline:

Camera JPEG
→ image decoder
→ ML Kit InputImage
→ ML Kit bounding box
→ image package crop
→ resize
→ TFLite

Determine whether ML Kit's bounding-box coordinate system is guaranteed to match the decoded image coordinate system used by:

`img.decodeImage(bytes)`

especially for:

* portrait camera images
* EXIF orientation
* front camera
* rotated frames
* mirrored preview

Do not assume they match.

Create a safe diagnostic method that can save/display ONE temporary debug crop locally during development.

The debug crop must clearly contain the detected face.

If the crop is wrong, fix the coordinate transformation/orientation before touching face matching.

---

# STEP 5 — VERIFY PREPROCESSING

Compare enrollment and kiosk preprocessing.

They MUST use exactly the same:

* image orientation handling
* face crop strategy
* crop padding
* resize dimensions
* RGB channel order
* normalization
* data type
* quantization handling

Document the exact preprocessing mathematically.

For example:

```text
pixel normalization =
(R - ?)
(G - ?)
(B - ?)
```

Do not assume the normalization is correct merely because MobileFaceNet commonly uses a particular normalization.

Verify it against THIS actual model.

---

# STEP 6 — VERIFY EMBEDDING QUALITY

For both enrollment and kiosk recognition calculate only:

```text
embeddingLength
L2Norm
minValue
maxValue
mean
```

Do NOT print the complete vector.

Expected checks:

```text
embeddingLength == modelOutputDimension
norm > 0
all values finite
```

If the embedding is all zeros, NaN, Infinity, or has an unexpected distribution, stop and fix inference.

---

# STEP 7 — VERIFY MATCHING

For every kiosk recognition attempt log:

```text
FACE_MATCH_DIAGNOSTICS

targetEmbeddingLength=
enrolledEmployeeCount=

employee=<employeeId>
embeddingLength=
similarity=

BEST_MATCH:
employeeId=
similarity=
threshold=
result=
```

Do not expose biometric vectors.

Also check:

```text
targetEmbedding.length == enrolledEmbedding.length
```

If dimensions differ, NEVER attempt matching.

---

# STEP 8 — SAME-PERSON SELF TEST

Create a development-only test/debug flow.

Use the SAME employee's enrolled face and another fresh camera capture of that same employee.

Calculate:

```text
similarity(enrollment, fresh_capture)
```

Then perform the reverse test:

```text
similarity(employee_A, employee_B)
```

The system should demonstrate that:

```text
same-person similarity
```

is meaningfully higher than:

```text
different-person similarity
```

Do NOT simply lower the threshold until the same person passes.

---

# STEP 9 — TEST WITH CONTROLLED CONDITIONS

Test using:

1. Same employee, same lighting
2. Same employee, different distance
3. Same employee, slight head rotation
4. Different employee
5. No face
6. Two faces
7. Poor lighting

Record the similarity scores.

Produce a table:

```text
Test
Expected
Actual similarity
Result
```

---

# STEP 10 — CHECK DATABASE DATA

Inspect one real enrolled employee record.

Verify:

```text
faceEnrollmentStatus
faceEmbedding exists
faceEmbedding length
employeeId
businessId
```

Verify SQLite contains the same employee and embedding.

Verify there is no serialization problem such as:

* String instead of List
* nested List
* null values
* truncated vector
* wrong numeric type
* wrong employee/business mapping

---

# STEP 11 — CHECK LOCAL CACHE

Kiosk startup must report:

```text
LOCAL_FACE_CACHE_DIAGNOSTICS

businessId=
employeesLoaded=
employeesWithEmbedding=
embeddingDimensions=
```

If:

```text
employeesWithEmbedding == 0
```

then recognition cannot work.

Find WHY the employees are not being synchronized.

Do not silently fall back to fake data.

---

# STEP 12 — CHECK THE ACTUAL FAILURE

After running the diagnostics, classify the root cause into ONE or more of:

A. Camera image problem
B. ML Kit face detection problem
C. Face bounding-box coordinate/orientation problem
D. Face crop problem
E. Image normalization problem
F. TFLite input tensor problem
G. TFLite output tensor problem
H. Embedding generation problem
I. Embedding database/storage problem
J. Local cache synchronization problem
K. Cosine similarity problem
L. Threshold/calibration problem
M. Multiple-face handling problem
N. Other

Do not make speculative fixes.

---

# STEP 13 — ONLY THEN FIX

Once the exact root cause is proven:

1. Implement the smallest correct fix.
2. Keep enrollment and kiosk preprocessing identical.
3. Keep recognition offline-first.
4. Remove any fake/demo fallback.
5. Keep attendance disabled when verification fails.
6. Preserve existing Admin, Master, SQLite, Firebase and attendance functionality.

---

# ACCEPTANCE CRITERIA

This phase is NOT complete until all of the following are demonstrated:

### Model

```text
Actual TFLite input/output verified
```

### Enrollment

```text
Real face
→ ML Kit detection
→ correct crop
→ valid embedding
→ stored in Firestore
→ stored/synced to SQLite
```

### Kiosk

```text
Camera
→ real face detected
→ correct crop
→ valid embedding
→ local employee found
→ cosine similarity calculated
→ correct employee matched
```

### Negative test

An unregistered/different employee must NOT match the registered employee merely because the threshold was lowered.

### Offline test

Disable internet:

```text
camera
→ face
→ local recognition
→ attendance
```

must still work for a properly synchronized employee.

### No fake data

There must be:

```text
NO fake embedding
NO demo employee
NO hardcoded employee
NO simulated face match
```

---

# FINAL REPORT REQUIRED

At the end provide:

## 1. Root Cause

One concise explanation of exactly why face verification was failing.

## 2. Evidence

Include actual diagnostic values such as:

```text
model input=
model output=
enrollment embedding length=
kiosk embedding length=
same-person similarity=
different-person similarity=
local employees with embeddings=
```

Do NOT include biometric vectors.

## 3. Files Changed

List every changed file and why it was changed.

## 4. Fix

Explain the exact technical fix.

## 5. Tests

List every test performed and PASS/FAIL.

## 6. Remaining Issues

If liveness, anti-spoofing, threshold calibration, or any other production issue remains, explicitly state it.

NEVER report "Face Verification Fixed" without actual successful same-person and negative-match test evidence.
