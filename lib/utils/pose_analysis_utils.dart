import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// =====================  Podešivi pragovi  =====================
/// — promijeni po potrebi bez diranja ostatka koda
class Thresholds {
  // ASLR
  static const double trunkInstabilityPctMax = 8.0; // ≤8% varijacije ramena–kuk
  static const double headInstabilityPctMax =
      10.0; // ≤10% varijacije nos–sredina ramena
  static const double kneeStraightMinDeg = 175.0; // koljeno ≳ 175° je "ravno"
  static const double movingStraightRatioMin =
      0.90; // pokretna noga ravna ≥90% frameova
  static const double stillStraightRatioMin =
      0.95; // nepokretna noga ravna ≥95% frameova

  // ASLR geometrija (hip flex)
  static const double aslrScore1Max = 30.0; // 0–30  → score 1
  static const double aslrScore2Max = 70.0; // 31–70 → score 2
  // >70 → score 3

  // Squat
  static const double squatKneeDepthDeg = 120.0; // oba koljena > 120° na dnu
  static const double squatTorsoUprightDeg =
      150.0; // prosjek shoulder–hip–ankle ≥ 150°
}

/// Traženi skup pokreta
enum ExerciseType {
  squat, // čučanj
  activeLegRaiseLeft, // ASLR – lijeva noga se podiže
  activeLegRaiseRight, // ASLR – desna noga se podiže
}

final Map<ExerciseType, String> exerciseNames = {
  ExerciseType.squat: 'Squat',
  ExerciseType.activeLegRaiseLeft: 'Active Straight Leg Raise (Left)',
  ExerciseType.activeLegRaiseRight: 'Active Straight Leg Raise (Right)',
};

class ExerciseAnalysisResult {
  final int score; // 0..3
  final Map<String, dynamic> features; // sve mjerne značajke + flagovi

  ExerciseAnalysisResult(this.score, this.features);
}

class PoseAnalysisUtils {
  // ----------------- Opće pomoćne funkcije -----------------

  /// Ugaoni kut u midPoint (0..180) između (first -> mid) i (last -> mid)
  static double angle(
    PoseLandmark firstPoint,
    PoseLandmark midPoint,
    PoseLandmark lastPoint,
  ) {
    final ax = firstPoint.x - midPoint.x;
    final ay = firstPoint.y - midPoint.y;
    final bx = lastPoint.x - midPoint.x;
    final by = lastPoint.y - midPoint.y;
    var radians = math.atan2(by, bx) - math.atan2(ay, ax);
    var deg = (radians * 180 / math.pi).abs();
    if (deg > 180) deg = 360 - deg;
    return deg;
  }

  static double dist(PoseLandmark a, PoseLandmark b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Relativna nestabilnost u % ( (max - min) / mean * 100 )
  static double instabilityPercent(List<double> series) {
    if (series.isEmpty) return 100;
    final minV = series.reduce(math.min);
    final maxV = series.reduce(math.max);
    final mean = series.reduce((a, b) => a + b) / series.length;
    if (mean == 0) return 100;
    return (maxV - minV) / mean * 100.0;
  }

  /// Je li koljeno praktički ravno (≈ 180°)
  static bool kneeStraight(
    PoseLandmark hip,
    PoseLandmark knee,
    PoseLandmark ankle, {
    double minDeg = Thresholds.kneeStraightMinDeg,
  }) {
    final k = angle(hip, knee, ankle);
    return k >= minDeg;
  }

  /// Hip flexion (0..~120): 180 - ∠(shoulder, hip, knee) — veće = bolja fleksija
  static double hipFlexionDeg(
    PoseLandmark shoulder,
    PoseLandmark hip,
    PoseLandmark knee,
  ) {
    final hipJoint = angle(shoulder, hip, knee);
    return 180.0 - hipJoint;
  }

  /// Srednja točka dviju točaka (za mid-shoulder, mid-hip itd.)
  static PoseLandmark _mid(PoseLandmark a, PoseLandmark b) => PoseLandmark(
    type: PoseLandmarkType.values.first, // dummy (nije bitan)
    x: (a.x + b.x) / 2,
    y: (a.y + b.y) / 2,
    z: (a.z + b.z) / 2,
    likelihood: 1.0,
  );

  // ----------------- Javni API -----------------

  static ExerciseAnalysisResult analyze(ExerciseType type, List<Pose> frames) {
    return analyzeWithContext(
      type,
      frames,
      painLowBack: false,
      painHamstringOrCalf: false,
    );
  }

  /// Verzija s self-report kontekstom (bol → automatski score=0)
  static ExerciseAnalysisResult analyzeWithContext(
    ExerciseType type,
    List<Pose> frames, {
    required bool painLowBack,
    required bool painHamstringOrCalf,
  }) {
    if (painLowBack == true || painHamstringOrCalf == true) {
      return ExerciseAnalysisResult(0, {
        'framesAnalyzed': frames.length,
        'painLowBack': painLowBack,
        'painHamstringOrCalf': painHamstringOrCalf,
        'note': 'Self-report pain present → score=0',
      });
    }

    switch (type) {
      case ExerciseType.squat:
        return _analyzeSquat(frames);
      case ExerciseType.activeLegRaiseLeft:
        return _analyzeASLR(frames, movingLeftLeg: true);
      case ExerciseType.activeLegRaiseRight:
        return _analyzeASLR(frames, movingLeftLeg: false);
    }
  }

  // ----------------- ASLR (Active Straight Leg Raise) -----------------
  static ExerciseAnalysisResult _analyzeASLR(
    List<Pose> frames, {
    required bool movingLeftLeg,
  }) {
    if (frames.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    // Serije za stabilnost trupa i glave
    final trunkDistSeries = <double>[];
    final headDistSeries = <double>[];

    // Serije za ravnost nogu i fleksiju
    final movingKneeStraightSeries = <bool>[];
    final stillKneeStraightSeries = <bool>[];
    final hipFlexSeries = <double>[];

    int validFrames = 0;

    for (final p in frames) {
      final ls = p.landmarks[PoseLandmarkType.leftShoulder];
      final rs = p.landmarks[PoseLandmarkType.rightShoulder];
      final lh = p.landmarks[PoseLandmarkType.leftHip];
      final rh = p.landmarks[PoseLandmarkType.rightHip];
      final lk = p.landmarks[PoseLandmarkType.leftKnee];
      final rk = p.landmarks[PoseLandmarkType.rightKnee];
      final la = p.landmarks[PoseLandmarkType.leftAnkle];
      final ra = p.landmarks[PoseLandmarkType.rightAnkle];
      final nose = p.landmarks[PoseLandmarkType.nose];

      if ([ls, rs, lh, rh, lk, rk, la, ra, nose].any((e) => e == null)) {
        continue;
      }

      final midShoulder = _mid(ls!, rs!);

      // 1) Stabilnost trupa i glave (distance kroz vrijeme)
      final trunkLeft = dist(ls, lh!);
      final trunkRight = dist(rs, rh!);
      trunkDistSeries.add((trunkLeft + trunkRight) / 2.0);

      final headToShoulders = dist(nose!, midShoulder);
      headDistSeries.add(headToShoulders);

      // 2) Ravnost nogu
      final movingHip = movingLeftLeg ? lh : rh;
      final movingKnee = movingLeftLeg ? lk : rk;
      final movingAnkle = movingLeftLeg ? la : ra;

      final stillHip = movingLeftLeg ? rh : lh;
      final stillKnee = movingLeftLeg ? rk : lk;
      final stillAnkle = movingLeftLeg ? ra : la;

      final movingStraight = kneeStraight(
        movingHip!,
        movingKnee!,
        movingAnkle!,
      );
      final stillStraight = kneeStraight(stillHip!, stillKnee!, stillAnkle!);

      movingKneeStraightSeries.add(movingStraight);
      stillKneeStraightSeries.add(stillStraight);

      // 3) Fleksija kuka (koristi ipsilateralno rame kao referencu)
      final ipsiShoulder = movingLeftLeg ? ls : rs;
      final hipFlex = hipFlexionDeg(ipsiShoulder!, movingHip, movingKnee);
      hipFlexSeries.add(hipFlex);

      validFrames++;
    }

    if (validFrames == 0 || hipFlexSeries.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    // Stabilnost
    final trunkInstabPct = instabilityPercent(trunkDistSeries);
    final headInstabPct = instabilityPercent(headDistSeries);
    final trunkStable = trunkInstabPct <= Thresholds.trunkInstabilityPctMax;
    final headStable = headInstabPct <= Thresholds.headInstabilityPctMax;

    // Ravnost nogu — udjeli "straight" frameova
    double ratio(List<bool> s) =>
        s.isEmpty ? 0.0 : s.where((b) => b).length / s.length;

    final movingStraightRatio = ratio(movingKneeStraightSeries);
    final stillStraightRatio = ratio(stillKneeStraightSeries);

    final movingStraightOk =
        movingStraightRatio >= Thresholds.movingStraightRatioMin;
    final stillStraightOk =
        stillStraightRatio >= Thresholds.stillStraightRatioMin;

    // Maks. fleksija kuka (za geometrijsku ocjenu)
    final hipFlexMax = hipFlexSeries.reduce(math.max);

    int scoreGeom;
    if (hipFlexMax <= Thresholds.aslrScore1Max)
      scoreGeom = 1;
    else if (hipFlexMax <= Thresholds.aslrScore2Max)
      scoreGeom = 2;
    else
      scoreGeom = 3;

    // Isključujući kriteriji
    final constraintsOk =
        (trunkStable && headStable && movingStraightOk && stillStraightOk);

    // Feature-i + flagovi
    final features = {
      'framesAnalyzed': validFrames,
      'movingSide': movingLeftLeg ? 'left' : 'right',

      // Metrike
      'hipFlexMaxDeg': hipFlexMax,
      'trunkInstabilityPct': trunkInstabPct,
      'headInstabilityPct': headInstabPct,
      'movingKneeStraightRatio': movingStraightRatio,
      'stillKneeStraightRatio': stillStraightRatio,

      // Flagovi (za izvještaj/HistoryScreen)
      'trunkStable': trunkStable,
      'headStable': headStable,
      'movingStraightOk': movingStraightOk,
      'stillStraightOk': stillStraightOk,
      'constraintsOk': constraintsOk,
      'scoreGeom': scoreGeom,
    };

    // Ako ne zadovolji isključujuće kriterije → konzervativno ograniči na 1
    if (!constraintsOk) {
      return ExerciseAnalysisResult(1, {
        ...features,
        'note':
            'Exclusion failed (trunk/head stability or leg straightness). Score constrained to 1.',
      });
    }

    return ExerciseAnalysisResult(scoreGeom, features);
  }

  // ----------------- Squat (čučanj) -----------------
  static ExerciseAnalysisResult _analyzeSquat(List<Pose> frames) {
    if (frames.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final leftKneeSeries = <double>[];
    final rightKneeSeries = <double>[];
    final torsoSeries = <double>[]; // veće = uspravnije (~180 najbolji)

    for (final p in frames) {
      final lh = p.landmarks[PoseLandmarkType.leftHip];
      final rh = p.landmarks[PoseLandmarkType.rightHip];
      final lk = p.landmarks[PoseLandmarkType.leftKnee];
      final rk = p.landmarks[PoseLandmarkType.rightKnee];
      final la = p.landmarks[PoseLandmarkType.leftAnkle];
      final ra = p.landmarks[PoseLandmarkType.rightAnkle];
      final ls = p.landmarks[PoseLandmarkType.leftShoulder];
      final rs = p.landmarks[PoseLandmarkType.rightShoulder];
      if ([lh, rh, lk, rk, la, ra, ls, rs].any((e) => e == null)) continue;

      final lKnee = angle(lh!, lk!, la!);
      final rKnee = angle(rh!, rk!, ra!);
      leftKneeSeries.add(lKnee);
      rightKneeSeries.add(rKnee);

      final lTorso = angle(ls!, lh, la);
      final rTorso = angle(rs!, rh, ra);
      torsoSeries.add((lTorso + rTorso) / 2.0);
    }

    if (leftKneeSeries.isEmpty) {
      return ExerciseAnalysisResult(0, {'framesAnalyzed': 0});
    }

    final lKneeMax = leftKneeSeries.reduce(math.max);
    final rKneeMax = rightKneeSeries.reduce(math.max);
    final torsoAvg = torsoSeries.reduce((a, b) => a + b) / torsoSeries.length;

    final depthOk =
        (lKneeMax > Thresholds.squatKneeDepthDeg &&
            rKneeMax > Thresholds.squatKneeDepthDeg);
    final torsoOk = torsoAvg >= Thresholds.squatTorsoUprightDeg;

    int score;
    if (depthOk && torsoOk)
      score = 3;
    else if (depthOk)
      score = 2;
    else
      score = 1;

    final reps = _countReps(
      List<double>.generate(
        leftKneeSeries.length,
        (i) => (leftKneeSeries[i] + rightKneeSeries[i]) / 2,
      ),
      downThresh: 125,
      upThresh: 105,
      smallerIsDown: false,
    );

    final features = {
      'framesAnalyzed': leftKneeSeries.length,
      'kneeFlexionMaxLeft': lKneeMax,
      'kneeFlexionMaxRight': rKneeMax,
      'torsoAngleAvg': torsoAvg,
      'depthOk': depthOk,
      'torsoOk': torsoOk,
      'reps': reps,
      'scoreHeuristic': score,
    };

    return ExerciseAnalysisResult(score, features);
  }

  // ----------------- Reps helper -----------------
  static bool _isMovingDown(
    double angle, {
    required double downThresh,
    required bool smallerIsDown,
  }) {
    return smallerIsDown ? angle <= downThresh : angle >= downThresh;
  }

  static bool _isMovingUp(
    double angle, {
    required double upThresh,
    required bool smallerIsDown,
  }) {
    return smallerIsDown ? angle >= upThresh : angle <= upThresh;
  }

  static int _countReps(
    List<double> series, {
    required double downThresh,
    required double upThresh,
    bool smallerIsDown = false,
  }) {
    if (series.isEmpty) return 0;
    int reps = 0;
    bool reachedDown = false;
    for (final v in series) {
      if (_isMovingDown(
        v,
        downThresh: downThresh,
        smallerIsDown: smallerIsDown,
      )) {
        reachedDown = true;
      }
      if (reachedDown &&
          _isMovingUp(v, upThresh: upThresh, smallerIsDown: smallerIsDown)) {
        reps++;
        reachedDown = false;
      }
    }
    return reps;
  }
}
