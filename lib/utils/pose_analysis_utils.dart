// lib/utils/pose_analysis_utils.dart

import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// === FMS catalog (3 most common tests) ===
enum ExerciseType {
  deepSquat,
  hurdleStep, // assume frontal view
  inlineLunge, // assume side/¾ view
}

final Map<ExerciseType, String> exerciseNames = {
  ExerciseType.deepSquat: 'Deep Squat',
  ExerciseType.hurdleStep: 'Hurdle Step',
  ExerciseType.inlineLunge: 'Inline Lunge',
};

class PoseAnalysisUtils {
  /// Angle at mid (degrees 0..180) between a->mid and b->mid.
  static double _angle(PoseLandmark a, PoseLandmark mid, PoseLandmark b) {
    final ax = a.x - mid.x;
    final ay = a.y - mid.y;
    final bx = b.x - mid.x;
    final by = b.y - mid.y;
    double rad = math.atan2(by, bx) - math.atan2(ay, ax);
    double deg = (rad * 180 / math.pi).abs();
    if (deg > 180) deg = 360 - deg;
    return deg;
  }

  /// Safe angle helper – returns null if any landmark missing.
  static double? _safeAngle(
    PoseLandmark? a,
    PoseLandmark? mid,
    PoseLandmark? b,
  ) {
    if (a == null || mid == null || b == null) return null;
    return _angle(a, mid, b);
  }

  /// Main dispatcher – returns 0..3 (0 = no data/invalid).
  static int scoreExercise(ExerciseType type, List<Pose> frames) {
    switch (type) {
      case ExerciseType.deepSquat:
        return _scoreDeepSquat(frames);
      case ExerciseType.hurdleStep:
        return _scoreHurdleStep(frames);
      case ExerciseType.inlineLunge:
        return _scoreInlineLunge(frames);
    }
  }

  // -----------------------------
  // Deep Squat (simplified)
  // -----------------------------
  //
  // Heuristics:
  // - Depth proxy: knee flexion (hip–knee–ankle) large => good depth.
  //   thresholdGoodDepth = 120°
  // - Torso upright proxy: shoulder–hip–ankle ≈ 180° (>= 150°)
  // - Compensation flags if torso not upright or knees too small (< 100°)
  static int _scoreDeepSquat(List<Pose> frames) {
    if (frames.isEmpty) return 0;

    const thresholdGoodDepth = 120.0;
    const thresholdMinKnee = 100.0;
    const thresholdTorso = 150.0;

    bool anyDepth = false;
    bool anyComp = false;

    for (final pose in frames) {
      final l = pose.landmarks;

      final lh = l[PoseLandmarkType.leftHip];
      final lk = l[PoseLandmarkType.leftKnee];
      final la = l[PoseLandmarkType.leftAnkle];
      final rh = l[PoseLandmarkType.rightHip];
      final rk = l[PoseLandmarkType.rightKnee];
      final ra = l[PoseLandmarkType.rightAnkle];
      final ls = l[PoseLandmarkType.leftShoulder];
      final rs = l[PoseLandmarkType.rightShoulder];

      final leftKnee = _safeAngle(lh, lk, la);
      final rightKnee = _safeAngle(rh, rk, ra);
      final leftTorso = _safeAngle(ls, lh, la);
      final rightTorso = _safeAngle(rs, rh, ra);

      if (leftKnee == null || rightKnee == null) continue;

      // depth
      if (leftKnee > thresholdGoodDepth && rightKnee > thresholdGoodDepth) {
        anyDepth = true;
      }

      // compensation checks
      if (leftKnee < thresholdMinKnee || rightKnee < thresholdMinKnee) {
        anyComp = true;
      }
      if (leftTorso != null && leftTorso < thresholdTorso) anyComp = true;
      if (rightTorso != null && rightTorso < thresholdTorso) anyComp = true;
    }

    if (!anyDepth) return 1; // no depth
    if (anyComp) return 2; // depth with compensations
    return 3; // clean
  }

  // -----------------------------
  // Hurdle Step (simplified, frontal)
  // -----------------------------
  //
  // Heuristics:
  // - Hip flexion (torso–hip–knee) indicates lifted leg height (~90° good).
  // - Pelvis stability proxy: difference in shoulder/hip horizontal line small.
  // - Knee/ankle tracking: knee x near hip/ankle x (very rough 2D proxy).
  static int _scoreHurdleStep(List<Pose> frames) {
    if (frames.isEmpty) return 0;

    // Tunables
    const hipFlexGoodMin = 70.0; // >= 70° suggests decent lift
    const hipFlexGoodMax = 120.0; // <= 120° keep within reasonable range
    const pelvisTiltTolerancePx = 40.0; // |leftHip.y - rightHip.y| small
    const kneeTrackTolerancePx = 60.0; // |knee.x - hip.x| small-ish

    bool goodLift = false;
    bool comp = false;

    for (final pose in frames) {
      final l = pose.landmarks;

      final ls = l[PoseLandmarkType.leftShoulder];
      final rs = l[PoseLandmarkType.rightShoulder];
      final lh = l[PoseLandmarkType.leftHip];
      final rh = l[PoseLandmarkType.rightHip];
      final lk = l[PoseLandmarkType.leftKnee];
      final rk = l[PoseLandmarkType.rightKnee];
      final la = l[PoseLandmarkType.leftAnkle];
      final ra = l[PoseLandmarkType.rightAnkle];

      // Choose the "lifted" leg by which knee is higher (smaller y).
      final bool leftHigher =
          (lk != null && rk != null) ? (lk.y < rk.y) : false;

      final hip = leftHigher ? lh : rh;
      final knee = leftHigher ? lk : rk;
      final shoulder = leftHigher ? ls : rs;

      // Hip flexion proxy: shoulder–hip–knee angle
      final hipFlex = _safeAngle(shoulder, hip, knee);

      if (hipFlex != null &&
          hipFlex >= hipFlexGoodMin &&
          hipFlex <= hipFlexGoodMax) {
        goodLift = true;
      }

      // Pelvis/shoulder level (rough)
      if (lh != null && rh != null) {
        if ((lh.y - rh.y).abs() > pelvisTiltTolerancePx) comp = true;
      }
      if (ls != null && rs != null) {
        if ((ls.y - rs.y).abs() > pelvisTiltTolerancePx) comp = true;
      }

      // Knee tracking (rough in 2D)
      if (hip != null && knee != null) {
        if ((knee.x - hip.x).abs() > kneeTrackTolerancePx) comp = true;
      }
    }

    if (!goodLift) return 1; // didn’t clear height
    if (comp) return 2; // cleared but compensations
    return 3; // clean
  }

  // -----------------------------
  // Inline Lunge (simplified, side/¾)
  // -----------------------------
  //
  // Heuristics:
  // - Front knee ~90° at bottom.
  // - Torso upright (shoulder–hip–knee ~ 160°+).
  // - Back leg reasonably extended (hip–knee–ankle large).
  static int _scoreInlineLunge(List<Pose> frames) {
    if (frames.isEmpty) return 0;

    const kneeTargetMin = 80.0;
    const kneeTargetMax = 110.0;
    const torsoUprightMin = 160.0;
    const backLegExtendMin = 150.0;

    bool reachedDepth = false;
    bool comp = false;

    for (final pose in frames) {
      final l = pose.landmarks;

      final ls = l[PoseLandmarkType.leftShoulder];
      final rs = l[PoseLandmarkType.rightShoulder];
      final lh = l[PoseLandmarkType.leftHip];
      final rh = l[PoseLandmarkType.rightHip];
      final lk = l[PoseLandmarkType.leftKnee];
      final rk = l[PoseLandmarkType.rightKnee];
      final la = l[PoseLandmarkType.leftAnkle];
      final ra = l[PoseLandmarkType.rightAnkle];

      if ([lh, rh, lk, rk, la, ra].any((e) => e == null)) continue;

      // Decide front knee by which knee is lower (bigger y) in a lunge step
      // (This is heuristic and depends on camera setup; tweak if needed.)
      final bool leftFront =
          (lk!.y > rk!.y); // larger y (lower on screen) assumed "front" knee

      final hipFront = leftFront ? lh! : rh!;
      final kneeFront = leftFront ? lk : rk;
      final ankleFront = leftFront ? la : ra;

      final hipBack = leftFront ? rh : lh;
      final kneeBack = leftFront ? rk : lk;
      final ankleBack = leftFront ? ra : la;

      final frontKnee = _safeAngle(hipFront, kneeFront, ankleFront);
      if (frontKnee != null &&
          frontKnee >= kneeTargetMin &&
          frontKnee <= kneeTargetMax) {
        reachedDepth = true;
      }

      // Torso upright proxy (both sides if available)
      final lTorso = _safeAngle(ls, lh, lk);
      final rTorso = _safeAngle(rs, rh, rk);
      final torsoUpright =
          ((lTorso == null || lTorso >= torsoUprightMin) &&
              (rTorso == null || rTorso >= torsoUprightMin));
      if (!torsoUpright) comp = true;

      // Back leg extension (hip–knee–ankle)
      final backLeg = _safeAngle(hipBack, kneeBack, ankleBack);
      if (backLeg != null && backLeg < backLegExtendMin) comp = true;
    }

    if (!reachedDepth) return 1;
    if (comp) return 2;
    return 3;
  }
}
