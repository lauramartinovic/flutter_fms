import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  PosePainter(
    this.poses,
    this.imageSize,
    this.rotation,
    this.cameraLensDirection,
  );

  // Clean, ML Kit–style paints
  final Paint _leftPaint =
      Paint()
        ..color = Colors.greenAccent
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke;

  final Paint _rightPaint =
      Paint()
        ..color = Colors.lightBlueAccent
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke;

  final Paint _jointPaint =
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    double sx(double x) {
      final scale = size.width / imageSize.width;
      if (cameraLensDirection == CameraLensDirection.front) {
        return size.width - x * scale;
      }
      return x * scale;
    }

    double sy(double y) {
      final scale = size.height / imageSize.height;
      return y * scale;
    }

    void drawJoint(PoseLandmark? lmk) {
      if (lmk == null) return;
      canvas.drawCircle(Offset(sx(lmk.x), sy(lmk.y)), 4.0, _jointPaint);
    }

    void drawBone(PoseLandmark? a, PoseLandmark? b, Paint p) {
      if (a == null || b == null) return;
      canvas.drawLine(Offset(sx(a.x), sy(a.y)), Offset(sx(b.x), sy(b.y)), p);
    }

    for (final pose in poses) {
      final l = pose.landmarks;

      // Draw joints
      for (final lm in l.values) {
        drawJoint(lm);
      }

      // Torso
      drawBone(
        l[PoseLandmarkType.leftShoulder],
        l[PoseLandmarkType.rightShoulder],
        _rightPaint,
      );
      drawBone(
        l[PoseLandmarkType.leftShoulder],
        l[PoseLandmarkType.leftHip],
        _leftPaint,
      );
      drawBone(
        l[PoseLandmarkType.rightShoulder],
        l[PoseLandmarkType.rightHip],
        _rightPaint,
      );
      drawBone(
        l[PoseLandmarkType.leftHip],
        l[PoseLandmarkType.rightHip],
        _rightPaint,
      );

      // Arms
      drawBone(
        l[PoseLandmarkType.leftShoulder],
        l[PoseLandmarkType.leftElbow],
        _leftPaint,
      );
      drawBone(
        l[PoseLandmarkType.leftElbow],
        l[PoseLandmarkType.leftWrist],
        _leftPaint,
      );
      drawBone(
        l[PoseLandmarkType.rightShoulder],
        l[PoseLandmarkType.rightElbow],
        _rightPaint,
      );
      drawBone(
        l[PoseLandmarkType.rightElbow],
        l[PoseLandmarkType.rightWrist],
        _rightPaint,
      );

      // Legs
      drawBone(
        l[PoseLandmarkType.leftHip],
        l[PoseLandmarkType.leftKnee],
        _leftPaint,
      );
      drawBone(
        l[PoseLandmarkType.leftKnee],
        l[PoseLandmarkType.leftAnkle],
        _leftPaint,
      );
      drawBone(
        l[PoseLandmarkType.rightHip],
        l[PoseLandmarkType.rightKnee],
        _rightPaint,
      );
      drawBone(
        l[PoseLandmarkType.rightKnee],
        l[PoseLandmarkType.rightAnkle],
        _rightPaint,
      );

      // Feet (optional but nice)
      drawBone(
        l[PoseLandmarkType.leftAnkle],
        l[PoseLandmarkType.leftFootIndex],
        _leftPaint,
      );
      drawBone(
        l[PoseLandmarkType.rightAnkle],
        l[PoseLandmarkType.rightFootIndex],
        _rightPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection;
  }
}
