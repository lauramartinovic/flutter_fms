// lib/screens/fms_capture/fms_capture_screen.dart
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';

import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/widgets/pose_painter.dart';
import 'package:flutter_fms/utils/pose_analysis_utils.dart';
import 'package:flutter_fms/screens/home/edit_profile_screen.dart';

class FMSCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FMSCaptureScreen({super.key, required this.cameras});

  @override
  State<FMSCaptureScreen> createState() => _FMSCaptureScreenState();
}

class _FMSCaptureScreenState extends State<FMSCaptureScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  String? _errorMessage;
  bool _isProcessingFrame = false;

  ExerciseType? _selectedExercise;
  int _currentFmsScore = 0;

  final List<Pose> _poseHistory = [];

  // STREAM mode -> brže za live preview
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  bool _isDetecting = false;
  List<Pose> _detectedPoses = [];

  // sample manje frameova u history
  int _frameCounter = 0;

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isNotEmpty) {
      _initializeCamera(widget.cameras[0]);
    } else {
      _errorMessage = 'No cameras found on this device.';
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  void _resetAnalysisState() {
    _poseHistory.clear();
    _currentFmsScore = 0;
    _frameCounter = 0;
  }

  Future<void> _initializeCamera(CameraDescription cam) async {
    try {
      await _cameraController?.dispose();
      _cameraController = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: true,
        // iOS -> BGRA8888, Android -> YUV420
        imageFormatGroup:
            defaultTargetPlatform == TargetPlatform.iOS
                ? ImageFormatGroup.bgra8888
                : ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();

      _cameraController!.startImageStream((CameraImage image) async {
        if (_isDetecting) return;
        _isDetecting = true;

        final rotation =
            InputImageRotationValue.fromRawValue(
              _cameraController!.description.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg;

        try {
          await _processCameraImage(image, rotation);

          // Spremi svaki 3. frame u history dok snimamo
          _frameCounter++;
          if (_isRecording &&
              _detectedPoses.isNotEmpty &&
              _frameCounter % 3 == 0) {
            _poseHistory.add(_detectedPoses.first);
          }
        } catch (e) {
          debugPrint('Pose detection error: $e');
        } finally {
          _isDetecting = false;
        }
      });

      if (mounted) setState(() => _errorMessage = null);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error initializing camera: ${e.description}';
      });
      await _cameraController?.dispose();
    }
  } // Add this field to your State class:

  Future<void> _processCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) async {
    if (_isProcessingFrame) return; // throttle frames
    _isProcessingFrame = true;

    try {
      late final InputImage inputImage;

      if (defaultTargetPlatform == TargetPlatform.android) {
        // ANDROID: Combine YUV420 planes into a single NV21 buffer
        final WriteBuffer allBytes = WriteBuffer();
        for (final Plane plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        final bytes = allBytes.done().buffer.asUint8List();

        inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            // ML Kit expects NV21 on Android
            format: InputImageFormat.nv21,
            // bytesPerRow should come from the Y (first) plane
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS: CameraImage is BGRA8888 (single plane)
        final bytes = image.planes.first.bytes;

        inputImage = InputImage.fromBytes(
          bytes: bytes,
          metadata: InputImageMetadata(
            size: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: image.planes.first.bytesPerRow,
          ),
        );
      } else {
        // Unsupported platform
        return;
      }

      final poses = await _poseDetector.processImage(inputImage);
      if (!mounted) return;
      setState(() => _detectedPoses = poses);
    } catch (e, st) {
      debugPrint('[_processCameraImage] error: $e\n$st');
    } finally {
      _isProcessingFrame = false;
    }
  }

  // --------- Recording controls (save only to device gallery) ----------
  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _errorMessage = 'Camera not initialized.');
      return;
    }
    if (_selectedExercise == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an exercise first.')),
      );
      return;
    }
    if (_cameraController!.value.isRecordingVideo) return;

    try {
      _resetAnalysisState();
      await _cameraController!.startVideoRecording();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Error starting recording: ${e.description}',
      );
    }
  }

  Future<void> _stopVideoRecordingAndSave() async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo)
      return;
    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      HapticFeedback.selectionClick();
      if (!mounted) return;
      setState(() => _isRecording = false);

      // Save to gallery via `gal`
      try {
        final has = await Gal.hasAccess(toAlbum: true) ?? false;
        if (!has) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putVideo(file.path, album: 'FMS Recordings');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video saved to gallery')));
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save video to gallery')),
        );
      }

      // Tek nakon snimanja izračunaj featurese i spremi sesiju
      await _finalizeAndSaveSessionScore();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Error stopping recording: ${e.description}',
      );
    }
  }

  // Optional: pick from gallery (no upload; score only)
  Future<void> _analyzeVideoFromGallery() async {
    if (_selectedExercise == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an exercise first.')),
      );
      return;
    }
    final picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    await _finalizeAndSaveSessionScore();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analyzed video and saved session score')),
    );
  }

  Future<void> _finalizeAndSaveSessionScore() async {
    ExerciseAnalysisResult? analysis;
    if (_selectedExercise != null) {
      analysis = PoseAnalysisUtils.analyze(_selectedExercise!, _poseHistory);
      _currentFmsScore = analysis.score;
    } else {
      _currentFmsScore = 0;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No user logged in.')),
      );
      return;
    }

    final exerciseName =
        _selectedExercise != null
            ? (exerciseNames[_selectedExercise!] ??
                _selectedExercise.toString())
            : 'Unknown';

    final session = FMSSessionModel(
      userId: user.uid,
      timestamp: DateTime.now(),
      exercise: exerciseName,
      rating: _currentFmsScore,
      notes: '',
      videoUrl: null,
    );

    try {
      final id = await FirestoreService().saveFMSession(session);

      // Spremi featurse u taj session dokument
      if (analysis != null) {
        await FirestoreService().updateFMSSession(
          sessionId: id,
          updates: {'features': analysis.features},
        );
      }

      _poseHistory.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save session: $e')));
    }
  }

  void _selectExerciseFromMenu(ExerciseType choice) {
    setState(() {
      _selectedExercise = choice;
    });
    _resetAnalysisState();
  }

  @override
  Widget build(BuildContext context) {
    const title = 'FMS Capture';
    final exLabel =
        _selectedExercise == null
            ? 'Select exercise'
            : (exerciseNames[_selectedExercise!] ??
                _selectedExercise.toString());

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(title: const Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final rotation =
        InputImageRotationValue.fromRawValue(
          _cameraController!.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    // -------- Overlay točno na korisniku (centered, cover scaling) --------
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: [
          PopupMenuButton<ExerciseType>(
            tooltip: 'Select exercise',
            icon: Row(
              children: [
                const Icon(Icons.fitness_center),
                const SizedBox(width: 6),
                Text(
                  _selectedExercise == null
                      ? 'Exercise'
                      : (exerciseNames[_selectedExercise!] ?? 'Exercise'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
            onSelected: _selectExerciseFromMenu,
            itemBuilder: (context) {
              return ExerciseType.values.map((e) {
                return PopupMenuItem<ExerciseType>(
                  value: e,
                  child: Text(exerciseNames[e] ?? e.toString()),
                );
              }).toList();
            },
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Edit Profile',
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final preview = _cameraController!.value.previewSize!;
          final bool swap =
              rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg;

          // “Upright” slika koju painter očekuje
          final Size imageSize =
              swap
                  ? Size(preview.height, preview.width)
                  : Size(preview.width, preview.height);

          // Napravimo “canvas” točno veličine input slike, pa ga FittedBox rastegne s cover
          final child = SizedBox(
            width: imageSize.width,
            height: imageSize.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController!),
                CustomPaint(
                  painter: PosePainter(
                    _detectedPoses,
                    imageSize,
                    rotation,
                    _cameraController!.description.lensDirection,
                  ),
                ),
              ],
            ),
          );

          return Center(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: imageSize.width,
                height: imageSize.height,
                child: child,
              ),
            ),
          );
        },
      ),

      // Bottom controls
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black54,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            FilledButton.icon(
              onPressed:
                  _isRecording
                      ? _stopVideoRecordingAndSave
                      : _startVideoRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.fiber_manual_record),
              label: Text(_isRecording ? 'Stop & Save' : 'Record'),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _isRecording
                        ? Colors.red
                        : Theme.of(context).colorScheme.primary,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _analyzeVideoFromGallery,
              icon: const Icon(Icons.video_library),
              label: const Text('Analyze from Gallery'),
            ),
          ],
        ),
      ),

      // Status chip
      floatingActionButtonLocation: FloatingActionButtonLocation.centerTop,
      floatingActionButton: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sports_gymnastics,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                _selectedExercise == null
                    ? 'Select exercise'
                    : (exerciseNames[_selectedExercise!] ?? 'Exercise'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.star, color: Colors.amber, size: 18),
              const SizedBox(width: 4),
              Text(
                'Score: $_currentFmsScore',
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
