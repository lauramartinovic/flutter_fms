import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Keep only 3 exercises (as agreed)
enum ExerciseType { overheadSquat, standardPushUp, forwardLunge }

enum _RepState { up, down }

final Map<ExerciseType, String> exerciseNames = {
  ExerciseType.overheadSquat: 'Overhead Squat',
  ExerciseType.standardPushUp: 'Push-Up',
  ExerciseType.forwardLunge: 'Forward Lunge',
};

class ExerciseAnalysisResult {
  final int score; // 0..3
  final Map<String, dynamic> features;

  ExerciseAnalysisResult(this.score, this.features);
}

class PoseAnalysisUtils {
  /// Angle at midPoint (in degrees 0..180) formed by A(mid<-first) and B(mid->last)
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

  /// Threshold crossing helper -> rough reps count from an angle time series.
  static int _countReps(
    List<double> series, {
    required double downThresh, // angle considered "at bottom" (or up)
    required double upThresh, // "at top"
    bool smallerIsDown = false, // whether going smaller angle means "down"
  }) {
    if (series.isEmpty) return 0;

    // renamed to avoid clash with Flutter's State<T>

    _RepState? state;
    int reps = 0;

    for (final v in series) {
      final isDown = smallerIsDown ? (v <= downThresh) : (v >= downThresh);
      final isUp = smallerIsDown ? (v >= upThresh) : (v <= upThresh);

      state ??= isUp ? _RepState.up : (isDown ? _RepState.down : null);
      if (state == null) continue;

      if (state == _RepState.up && isDown) {
        state = _RepState.down;
      } else if (state == _RepState.down && isUp) {
        state = _RepState.up;
        reps++; // completed one full cycle
      }
    }
    return reps;
  }

  /// Public API: get score + features for a movement, from a list of frames/poses.
  static ExerciseAnalysisResult analyze(ExerciseType type, List<Pose> frames) {
    switch (type) {
      case ExerciseType.overheadSquat:
        return _analyzeOverheadSquat(frames);
      case ExerciseType.standardPushUp:
        return _analyzePushUp(frames);
      case ExerciseType.forwardLunge:
        return _analyzeLunge(frames);
    }
  }

  /// Threshold crossing helper -> rough reps count from an angle time series.

  // ---------- Overhead Squat ----------
  // Heuristics closer to FMS (still 2D):
  // 3: Hips below knees (depth), knees track (no valgus), arms stay near overhead (shoulder-elbow-wrist ~180), torso relatively upright.
  // 2: Depth achieved but with compensations (valgus OR arms drop OR torso lean).
  // 1: No depth.
  // 0: No data.
  static ExerciseAnalysisResult _analyzeOverheadSquat(List<Pose> frames) {
    if (frames.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final leftKneeSeries = <double>[];
    final rightKneeSeries = <double>[];
    final armSeries =
        <
          double
        >[]; // average of left/right (shoulder-elbow-wrist), higher is better (close to 180)
    final torsoSeries =
        <
          double
        >[]; // average torso angle (shoulder-hip-ankle), higher is more upright

    bool anyDepth = false;
    bool valgusOrArmsOrTorsoComp = false;

    for (final p in frames) {
      final lh = p.landmarks[PoseLandmarkType.leftHip];
      final rh = p.landmarks[PoseLandmarkType.rightHip];
      final lk = p.landmarks[PoseLandmarkType.leftKnee];
      final rk = p.landmarks[PoseLandmarkType.rightKnee];
      final la = p.landmarks[PoseLandmarkType.leftAnkle];
      final ra = p.landmarks[PoseLandmarkType.rightAnkle];
      final ls = p.landmarks[PoseLandmarkType.leftShoulder];
      final rs = p.landmarks[PoseLandmarkType.rightShoulder];
      final le = p.landmarks[PoseLandmarkType.leftElbow];
      final re = p.landmarks[PoseLandmarkType.rightElbow];
      final lw = p.landmarks[PoseLandmarkType.leftWrist];
      final rw = p.landmarks[PoseLandmarkType.rightWrist];

      if ([
        lh,
        rh,
        lk,
        rk,
        la,
        ra,
        ls,
        rs,
        le,
        re,
        lw,
        rw,
      ].any((e) => e == null)) {
        continue;
      }

      final lKnee = angle(lh!, lk!, la!);
      final rKnee = angle(rh!, rk!, ra!);
      leftKneeSeries.add(lKnee);
      rightKneeSeries.add(rKnee);

      // Arms overhead: shoulder–elbow–wrist angle close to 180
      final lArm = angle(ls!, le!, lw!);
      final rArm = angle(rs!, re!, rw!);
      armSeries.add((lArm + rArm) / 2);

      // Torso upright: shoulder–hip–ankle angle close to 180
      final lTorso = angle(ls, lh, la);
      final rTorso = angle(rs, rh, ra);
      torsoSeries.add((lTorso + rTorso) / 2);
    }

    if (leftKneeSeries.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    // Depth: consider both knees > 120 at bottom (heuristic)
    final lKneeMax = leftKneeSeries.reduce(math.max);
    final rKneeMax = rightKneeSeries.reduce(math.max);
    if (lKneeMax > 120 && rKneeMax > 120) {
      anyDepth = true;
    }

    // Compensations:
    // - Arms drop: average arms below ~160
    final armAvg = armSeries.reduce((a, b) => a + b) / armSeries.length;
    final armsDrop = armAvg < 160;

    // - Torso lean: average torso below ~150
    final torsoAvg = torsoSeries.reduce((a, b) => a + b) / torsoSeries.length;
    final torsoLean = torsoAvg < 150;

    // - Knee valgus (very rough 2D proxy): compare knee x vs ankle x relative to hip x — skipped (camera/frontal needed).
    // As a proxy, if min knee angle is very small (<100) at any point, flag compensation
    final lKneeMin = leftKneeSeries.reduce(math.min);
    final rKneeMin = rightKneeSeries.reduce(math.min);
    final kneeComp = (lKneeMin < 100 || rKneeMin < 100);

    valgusOrArmsOrTorsoComp = armsDrop || torsoLean || kneeComp;

    // Count "reps": knee angle passing down/up thresholds
    final reps = _countReps(
      List<double>.generate(
        leftKneeSeries.length,
        (i) => (leftKneeSeries[i] + rightKneeSeries[i]) / 2,
      ),
      downThresh: 125,
      upThresh:
          105, // go down beyond 125, back up below ~105 (heuristic direction=larger=down)
      smallerIsDown: false,
    );

    final features = {
      'framesAnalyzed': leftKneeSeries.length,
      'kneeFlexionMaxLeft': lKneeMax,
      'kneeFlexionMaxRight': rKneeMax,
      'kneeFlexionMinLeft': lKneeMin,
      'kneeFlexionMinRight': rKneeMin,
      'armsAngleAvg': armAvg,
      'torsoAngleAvg': torsoAvg,
      'reps': reps,
    };

    int score;
    if (anyDepth && !valgusOrArmsOrTorsoComp)
      score = 3;
    else if (anyDepth)
      score = 2;
    else
      score = 1;

    return ExerciseAnalysisResult(score, features);
  }

  // ---------- Push-Up ----------
  // 3: Body straight (shoulder-hip-ankle near 180), elbow ≤ 90 at bottom, consistent reps.
  // 2: Full depth but body sags/pikes.
  // 1: No full depth.
  // 0: No data.
  static ExerciseAnalysisResult _analyzePushUp(List<Pose> frames) {
    if (frames.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final elbowSeries = <double>[]; // min is good depth (<=90)
    final bodySeries = <double>[]; // higher (~180) is straighter

    for (final p in frames) {
      final ls = p.landmarks[PoseLandmarkType.leftShoulder];
      final rs = p.landmarks[PoseLandmarkType.rightShoulder];
      final le = p.landmarks[PoseLandmarkType.leftElbow];
      final re = p.landmarks[PoseLandmarkType.rightElbow];
      final lw = p.landmarks[PoseLandmarkType.leftWrist];
      final rw = p.landmarks[PoseLandmarkType.rightWrist];
      final lh = p.landmarks[PoseLandmarkType.leftHip];
      final rh = p.landmarks[PoseLandmarkType.rightHip];
      final la = p.landmarks[PoseLandmarkType.leftAnkle];
      final ra = p.landmarks[PoseLandmarkType.rightAnkle];

      if ([ls, rs, le, re, lw, rw, lh, rh, la, ra].any((e) => e == null)) {
        continue;
      }

      final leftElbow = angle(ls!, le!, lw!);
      final rightElbow = angle(rs!, re!, rw!);
      elbowSeries.add(math.min(leftElbow, rightElbow));

      final leftBody = angle(ls, lh!, la!);
      final rightBody = angle(rs, rh!, ra!);
      bodySeries.add((leftBody + rightBody) / 2);
    }

    if (elbowSeries.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final elbowMin = elbowSeries.reduce(math.min);
    final bodyAvg = bodySeries.reduce((a, b) => a + b) / bodySeries.length;

    final fullDepth = elbowMin <= 90;
    final bodyStraight = bodyAvg >= 170;

    final reps = _countReps(
      elbowSeries,
      downThresh: 95,
      upThresh: 150, // go down <=95 then up >=150
      smallerIsDown: true,
    );

    final features = {
      'framesAnalyzed': elbowSeries.length,
      'elbowMin': elbowMin,
      'bodyAvg': bodyAvg,
      'reps': reps,
    };

    int score;
    if (fullDepth && bodyStraight)
      score = 3;
    else if (fullDepth)
      score = 2;
    else
      score = 1;

    return ExerciseAnalysisResult(score, features);
  }

  // ---------- Forward Lunge ----------
  // 3: Front knee near 90 (85..110), torso upright (>=160), no big collapse.
  // 2: Reached depth but compensation.
  // 1: No depth.
  // 0: No data.
  static ExerciseAnalysisResult _analyzeLunge(List<Pose> frames) {
    if (frames.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final frontKneeSeries =
        <double>[]; // knee angle (hip-knee-ankle) of the "front" leg
    final torsoSeries = <double>[];

    for (final p in frames) {
      final ls = p.landmarks[PoseLandmarkType.leftShoulder];
      final rs = p.landmarks[PoseLandmarkType.rightShoulder];
      final lh = p.landmarks[PoseLandmarkType.leftHip];
      final rh = p.landmarks[PoseLandmarkType.rightHip];
      final lk = p.landmarks[PoseLandmarkType.leftKnee];
      final rk = p.landmarks[PoseLandmarkType.rightKnee];
      final la = p.landmarks[PoseLandmarkType.leftAnkle];
      final ra = p.landmarks[PoseLandmarkType.rightAnkle];

      if ([ls, rs, lh, rh, lk, rk, la, ra].any((e) => e == null)) {
        continue;
      }

      final leftKnee = angle(lh!, lk!, la!);
      final rightKnee = angle(rh!, rk!, ra!);

      // Roughly pick "front" knee by smaller y (more toward camera/top depends on view; heuristic)
      final useLeftAsFront = lk!.y < rk!.y;
      final frontKnee = useLeftAsFront ? leftKnee : rightKnee;
      frontKneeSeries.add(frontKnee);

      final lTorso = angle(ls!, lh, lk);
      final rTorso = angle(rs!, rh, rk);
      torsoSeries.add((lTorso + rTorso) / 2);
    }

    if (frontKneeSeries.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final kneeMin = frontKneeSeries.reduce(math.min);
    final kneeMax = frontKneeSeries.reduce(math.max);
    final torsoAvg = torsoSeries.reduce((a, b) => a + b) / torsoSeries.length;

    final depth =
        (kneeMin >= 85 && kneeMin <= 110) || (kneeMax >= 85 && kneeMax <= 110);
    final torsoUpright = torsoAvg >= 160;

    final reps = _countReps(
      frontKneeSeries,
      downThresh: 95,
      upThresh: 120, // go down near 90, back to ~>120
      smallerIsDown:
          (false), // larger angle ~ straighter; but we used min closeness to 90 too
    );

    final features = {
      'framesAnalyzed': frontKneeSeries.length,
      'frontKneeMin': kneeMin,
      'frontKneeMax': kneeMax,
      'torsoAvg': torsoAvg,
      'reps': reps,
    };

    int score;
    if (depth && torsoUpright)
      score = 3;
    else if (depth)
      score = 2;
    else
      score = 1;

    return ExerciseAnalysisResult(score, features);
  }
}
