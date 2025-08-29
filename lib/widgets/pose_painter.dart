// lib/widgets/pose_painter.dart

import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:camera/camera.dart';

class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection
  cameraLensDirection; // To correctly flip for front camera

  PosePainter(
    this.poses,
    this.imageSize,
    this.rotation,
    this.cameraLensDirection,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..color = Colors.greenAccent;

    // Helper to scale points correctly for display
    void paintLandmark(PoseLandmark landmark) {
      final Offset offset = Offset(
        _scaleX(landmark.x, size, cameraLensDirection),
        _scaleY(landmark.y, size),
      );
      canvas.drawCircle(offset, 6.0, paint);
    }

    void paintLine(PoseLandmark start, PoseLandmark end) {
      final Offset startOffset = Offset(
        _scaleX(start.x, size, cameraLensDirection),
        _scaleY(start.y, size),
      );
      final Offset endOffset = Offset(
        _scaleX(end.x, size, cameraLensDirection),
        _scaleY(end.y, size),
      );
      canvas.drawLine(startOffset, endOffset, paint);
    }

    for (final pose in poses) {
      // Draw all landmarks
      for (final landmark in pose.landmarks.values) {
        paintLandmark(landmark);
      }

      // Draw connections for common body parts
      void drawSegment(PoseLandmarkType type1, PoseLandmarkType type2) {
        final PoseLandmark? landmark1 = pose.landmarks[type1];
        final PoseLandmark? landmark2 = pose.landmarks[type2];
        if (landmark1 != null && landmark2 != null) {
          paintLine(landmark1, landmark2);
        }
      }

      // Face
      drawSegment(PoseLandmarkType.nose, PoseLandmarkType.rightEyeInner);
      drawSegment(PoseLandmarkType.rightEyeInner, PoseLandmarkType.rightEye);
      drawSegment(PoseLandmarkType.rightEye, PoseLandmarkType.rightEyeOuter);
      drawSegment(PoseLandmarkType.rightEyeOuter, PoseLandmarkType.rightEar);
      drawSegment(PoseLandmarkType.nose, PoseLandmarkType.leftEyeInner);
      drawSegment(PoseLandmarkType.leftEyeInner, PoseLandmarkType.leftEye);
      drawSegment(PoseLandmarkType.leftEye, PoseLandmarkType.leftEyeOuter);
      drawSegment(PoseLandmarkType.leftEyeOuter, PoseLandmarkType.leftEar);
      drawSegment(PoseLandmarkType.rightEar, PoseLandmarkType.rightMouth);
      drawSegment(PoseLandmarkType.leftEar, PoseLandmarkType.leftMouth);
      drawSegment(PoseLandmarkType.rightMouth, PoseLandmarkType.leftMouth);

      // Torso
      drawSegment(
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
      );
      drawSegment(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip);
      drawSegment(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip);
      drawSegment(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip);

      // Arms
      drawSegment(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow);
      drawSegment(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist);
      drawSegment(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow);
      drawSegment(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist);

      // Legs
      drawSegment(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee);
      drawSegment(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle);
      drawSegment(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee);
      drawSegment(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle);
      drawSegment(PoseLandmarkType.leftAnkle, PoseLandmarkType.leftHeel);
      drawSegment(PoseLandmarkType.rightAnkle, PoseLandmarkType.rightHeel);
      drawSegment(PoseLandmarkType.leftHeel, PoseLandmarkType.leftFootIndex);
      drawSegment(PoseLandmarkType.rightHeel, PoseLandmarkType.rightFootIndex);
      drawSegment(PoseLandmarkType.leftAnkle, PoseLandmarkType.leftFootIndex);
      drawSegment(PoseLandmarkType.rightAnkle, PoseLandmarkType.rightFootIndex);
    }
  }

  @override
  bool shouldRepaint(covariant PosePainter oldDelegate) {
    return oldDelegate.poses != poses; // Only repaint if poses data changes
  }

  // Scaling helper functions based on ML Kit's input image and display size
  double _scaleX(double x, Size size, CameraLensDirection cameraLensDirection) {
    double scale = size.width / imageSize.width;
    if (cameraLensDirection == CameraLensDirection.front) {
      // Flip X for front camera to mirror user's view
      return size.width - (x * scale);
    }
    return x * scale;
  }

  double _scaleY(double y, Size size) {
    double scale = size.height / imageSize.height;
    return y * scale;
  }
}
