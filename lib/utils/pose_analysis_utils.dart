import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// 20-slot catalog-ready list (expand/adjust freely)
enum ExerciseType {
  overheadSquat,
  inlineLungeLeft,
  inlineLungeRight,
  hurdleStepLeft,
  hurdleStepRight,
  shoulderMobilityLeft,
  shoulderMobilityRight,
  activeStraightLegRaiseLeft,
  activeStraightLegRaiseRight,
  trunkStabilityPushUp,
  rotaryStabilityLeft,
  rotaryStabilityRight,
  standardSquat,
  forwardLunge,
  standardPushUp,
  plankHold,
  singleLegBalanceLeft,
  singleLegBalanceRight,
  singleLegSquatLeft,
  singleLegSquatRight,
}

final Map<ExerciseType, String> exerciseNames = {
  ExerciseType.overheadSquat: 'Overhead Squat',
  ExerciseType.inlineLungeLeft: 'Inline Lunge (Left)',
  ExerciseType.inlineLungeRight: 'Inline Lunge (Right)',
  ExerciseType.hurdleStepLeft: 'Hurdle Step (Left)',
  ExerciseType.hurdleStepRight: 'Hurdle Step (Right)',
  ExerciseType.shoulderMobilityLeft: 'Shoulder Mobility (Left)',
  ExerciseType.shoulderMobilityRight: 'Shoulder Mobility (Right)',
  ExerciseType.activeStraightLegRaiseLeft: 'Active Straight-Leg Raise (Left)',
  ExerciseType.activeStraightLegRaiseRight: 'Active Straight-Leg Raise (Right)',
  ExerciseType.trunkStabilityPushUp: 'Trunk Stability Push-Up',
  ExerciseType.rotaryStabilityLeft: 'Rotary Stability (Left)',
  ExerciseType.rotaryStabilityRight: 'Rotary Stability (Right)',
  ExerciseType.standardSquat: 'Bodyweight Squat',
  ExerciseType.forwardLunge: 'Forward Lunge',
  ExerciseType.standardPushUp: 'Push-Up',
  ExerciseType.plankHold: 'Plank Hold',
  ExerciseType.singleLegBalanceLeft: 'Single-Leg Balance (Left)',
  ExerciseType.singleLegBalanceRight: 'Single-Leg Balance (Right)',
  ExerciseType.singleLegSquatLeft: 'Single-Leg Squat (Left)',
  ExerciseType.singleLegSquatRight: 'Single-Leg Squat (Right)',
};

class PoseAnalysisUtils {
  /// Angle at midPoint (in degrees, 0..180) between firstPoint -> midPoint -> lastPoint.
  static double angle(
    PoseLandmark firstPoint,
    PoseLandmark midPoint,
    PoseLandmark lastPoint,
  ) {
    final ax = firstPoint.x - midPoint.x;
    final ay = firstPoint.y - midPoint.y;
    final bx = lastPoint.x - midPoint.x;
    final by = lastPoint.y - midPoint.y;
    double radians = math.atan2(by, bx) - math.atan2(ay, ax);
    double deg = (radians * 180 / math.pi).abs();
    if (deg > 180) deg = 360 - deg;
    return deg;
  }

  /// Score dispatcher – extend with specific rules per exercise.
  static int scoreExercise(ExerciseType type, List<Pose> frames) {
    switch (type) {
      case ExerciseType.overheadSquat:
      case ExerciseType.standardSquat:
        return _scoreSquat(frames);
      case ExerciseType.trunkStabilityPushUp:
      case ExerciseType.standardPushUp:
        return _scorePushUp(frames);
      case ExerciseType.inlineLungeLeft:
      case ExerciseType.inlineLungeRight:
      case ExerciseType.forwardLunge:
        return _scoreLunge(frames);
      // TODO: implement additional tests with similar pattern:
      // hurdle step, shoulder mobility, ASLR, rotary stability, single-leg tasks, plank progression
      default:
        // Not implemented yet -> neutral value
        return frames.isEmpty ? 0 : 1;
    }
  }

  /// Simplified squat scoring:
  /// 3 = depth achieved (knee flexion large) AND torso relatively upright
  /// 2 = depth achieved but compensations
  /// 1 = no depth
  /// 0 = no data
  static int _scoreSquat(List<Pose> frames) {
    if (frames.isEmpty) return 0;
    bool anyDepth = false;
    bool anyComp = false;

    for (final pose in frames) {
      final lh = pose.landmarks[PoseLandmarkType.leftHip];
      final lk = pose.landmarks[PoseLandmarkType.leftKnee];
      final la = pose.landmarks[PoseLandmarkType.leftAnkle];
      final rh = pose.landmarks[PoseLandmarkType.rightHip];
      final rk = pose.landmarks[PoseLandmarkType.rightKnee];
      final ra = pose.landmarks[PoseLandmarkType.rightAnkle];
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];

      if ([lh, lk, la, rh, rk, ra, ls, rs].any((e) => e == null)) continue;

      // Knee flexion angles (hip-knee-ankle)
      final lKnee = angle(lh!, lk!, la!);
      final rKnee = angle(rh!, rk!, ra!);

      // Heuristic "depth": > 120° indicates good flexion (tune as needed)
      if (lKnee > 120 && rKnee > 120) anyDepth = true;

      // Torso upright (shoulder-hip-ankle near 180°)
      final lTorso = angle(ls!, lh, la);
      final rTorso = angle(rs!, rh, ra);
      final torsoUpright = (lTorso >= 150 && rTorso >= 150);
      if (!torsoUpright) anyComp = true;

      // Basic knee tracking: if knee angle too small (< 150), flag compensation
      if (lKnee < 100 || rKnee < 100) anyComp = true;
    }

    if (anyDepth && !anyComp) return 3;
    if (anyDepth) return 2;
    return 1;
  }

  /// Simplified push-up scoring:
  /// 3 = full depth (elbow ≤ 90°) and body straight (shoulder-hip-ankle ~180°)
  /// 2 = full depth with body sag/pike
  /// 1 = no full depth
  /// 0 = no data
  static int _scorePushUp(List<Pose> frames) {
    if (frames.isEmpty) return 0;
    bool fullDepth = false;
    bool misalign = false;

    for (final pose in frames) {
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
      final le = pose.landmarks[PoseLandmarkType.leftElbow];
      final re = pose.landmarks[PoseLandmarkType.rightElbow];
      final lw = pose.landmarks[PoseLandmarkType.leftWrist];
      final rw = pose.landmarks[PoseLandmarkType.rightWrist];
      final lh = pose.landmarks[PoseLandmarkType.leftHip];
      final rh = pose.landmarks[PoseLandmarkType.rightHip];
      final la = pose.landmarks[PoseLandmarkType.leftAnkle];
      final ra = pose.landmarks[PoseLandmarkType.rightAnkle];

      if ([ls, rs, le, re, lw, rw, lh, rh, la, ra].any((e) => e == null))
        continue;

      final leftElbow = angle(ls!, le!, lw!);
      final rightElbow = angle(rs!, re!, rw!);
      if (leftElbow <= 90 || rightElbow <= 90) fullDepth = true;

      final leftBody = angle(ls, lh!, la!);
      final rightBody = angle(rs, rh!, ra!);
      final bodyStraight = (leftBody >= 170 && rightBody >= 170);
      if (!bodyStraight) misalign = true;
    }

    if (fullDepth && !misalign) return 3;
    if (fullDepth) return 2;
    return 1;
  }

  /// Simplified lunge scoring:
  /// 3 = front knee ~90°, torso upright
  /// 2 = reached depth but compensation
  /// 1 = no depth
  /// 0 = no data
  static int _scoreLunge(List<Pose> frames) {
    if (frames.isEmpty) return 0;
    bool depth = false;
    bool comp = false;

    for (final pose in frames) {
      final ls = pose.landmarks[PoseLandmarkType.leftShoulder];
      final rs = pose.landmarks[PoseLandmarkType.rightShoulder];
      final lh = pose.landmarks[PoseLandmarkType.leftHip];
      final rh = pose.landmarks[PoseLandmarkType.rightHip];
      final lk = pose.landmarks[PoseLandmarkType.leftKnee];
      final rk = pose.landmarks[PoseLandmarkType.rightKnee];
      final la = pose.landmarks[PoseLandmarkType.leftAnkle];
      final ra = pose.landmarks[PoseLandmarkType.rightAnkle];

      if ([ls, rs, lh, rh, lk, rk, la, ra].any((e) => e == null)) continue;

      // Decide "front" knee roughly by lower y (depends on camera angle; heuristic)
      final leftKneeAngle = angle(lh!, lk!, la!);
      final rightKneeAngle = angle(rh!, rk!, ra!);
      final frontKneeAngle = (lk!.y < rk!.y) ? leftKneeAngle : rightKneeAngle;

      if (frontKneeAngle >= 85 && frontKneeAngle <= 110) depth = true;

      final lTorso = angle(ls!, lh, lk);
      final rTorso = angle(rs!, rh, rk);
      if (lTorso < 160 || rTorso < 160) comp = true;
    }

    if (depth && !comp) return 3;
    if (depth) return 2;
    return 1;
  }
}
