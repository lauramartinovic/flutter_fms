import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;

  /// Size of the input frame in UPRIGHT coordinates (after rotation).
  final Size imageSizeUpright;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  PosePainter(
    this.poses,
    this.imageSizeUpright,
    this.rotation,
    this.lensDirection,
  );

  final Paint _leftPaint =
      Paint()
        ..color = Colors.greenAccent
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;

  final Paint _rightPaint =
      Paint()
        ..color = Colors.lightBlueAccent
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke;

  final Paint _jointPaint =
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final double imgW = imageSizeUpright.width;
    final double imgH = imageSizeUpright.height;

    // Same “cover” fit as CameraPreview
    final scale = _coverScale(canvasSize, Size(imgW, imgH));
    final dx = (canvasSize.width - imgW * scale) / 2.0;
    final dy = (canvasSize.height - imgH * scale) / 2.0;

    Offset mapPoint(double x, double y) {
      // Mirror for FRONT camera to match what user sees
      if (lensDirection == CameraLensDirection.front) {
        x = imgW - x;
      }
      return Offset(x * scale + dx, y * scale + dy);
    }

    void joint(PoseLandmark? p) {
      if (p == null) return;
      canvas.drawCircle(mapPoint(p.x, p.y), 4, _jointPaint);
    }

    void bone(PoseLandmark? a, PoseLandmark? b, Paint paint) {
      if (a == null || b == null) return;
      canvas.drawLine(mapPoint(a.x, a.y), mapPoint(b.x, b.y), paint);
    }

    for (final pose in poses) {
      final l = pose.landmarks;

      // joints
      for (final lm in l.values) {
        joint(lm);
      }

      // torso
      bone(
        l[PoseLandmarkType.leftShoulder],
        l[PoseLandmarkType.rightShoulder],
        _rightPaint,
      );
      bone(
        l[PoseLandmarkType.leftShoulder],
        l[PoseLandmarkType.leftHip],
        _leftPaint,
      );
      bone(
        l[PoseLandmarkType.rightShoulder],
        l[PoseLandmarkType.rightHip],
        _rightPaint,
      );
      bone(
        l[PoseLandmarkType.leftHip],
        l[PoseLandmarkType.rightHip],
        _rightPaint,
      );

      // arms
      bone(
        l[PoseLandmarkType.leftShoulder],
        l[PoseLandmarkType.leftElbow],
        _leftPaint,
      );
      bone(
        l[PoseLandmarkType.leftElbow],
        l[PoseLandmarkType.leftWrist],
        _leftPaint,
      );
      bone(
        l[PoseLandmarkType.rightShoulder],
        l[PoseLandmarkType.rightElbow],
        _rightPaint,
      );
      bone(
        l[PoseLandmarkType.rightElbow],
        l[PoseLandmarkType.rightWrist],
        _rightPaint,
      );

      // legs
      bone(
        l[PoseLandmarkType.leftHip],
        l[PoseLandmarkType.leftKnee],
        _leftPaint,
      );
      bone(
        l[PoseLandmarkType.leftKnee],
        l[PoseLandmarkType.leftAnkle],
        _leftPaint,
      );
      bone(
        l[PoseLandmarkType.rightHip],
        l[PoseLandmarkType.rightKnee],
        _rightPaint,
      );
      bone(
        l[PoseLandmarkType.rightKnee],
        l[PoseLandmarkType.rightAnkle],
        _rightPaint,
      );

      // feet
      bone(
        l[PoseLandmarkType.leftAnkle],
        l[PoseLandmarkType.leftFootIndex],
        _leftPaint,
      );
      bone(
        l[PoseLandmarkType.rightAnkle],
        l[PoseLandmarkType.rightFootIndex],
        _rightPaint,
      );
    }
  }

  double _coverScale(Size canvas, Size content) {
    final sx = canvas.width / content.width;
    final sy = canvas.height / content.height;
    return sx > sy ? sx : sy;
    // (This emulates BoxFit.cover from CameraPreview.)
  }

  @override
  bool shouldRepaint(covariant PosePainter old) {
    return old.poses != poses ||
        old.imageSizeUpright != imageSizeUpright ||
        old.rotation != rotation ||
        old.lensDirection != lensDirection;
  }
}
