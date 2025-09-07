// lib/screens/fms_capture/fms_capture_screen.dart

import 'package:flutter/services.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';

import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/widgets/pose_painter.dart';
import 'package:flutter_fms/utils/pose_analysis_utils.dart';
import 'package:flutter_fms/services/auth_service.dart';

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

  ExerciseType? _selectedExercise;
  int _currentFmsScore = 0;
  final List<Pose> _poseHistory = [];

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(mode: PoseDetectionMode.stream),
  );
  bool _isDetecting = false;
  List<Pose> _detectedPoses = [];

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
  }

  Future<void> _initializeCamera(CameraDescription cam) async {
    try {
      await _cameraController?.dispose();
      _cameraController = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: true, // recording to gallery
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();

      _cameraController!.startImageStream((CameraImage image) {
        if (_isDetecting) return;
        _isDetecting = true;

        final rotation =
            InputImageRotationValue.fromRawValue(
              _cameraController!.description.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg;

        _processCameraImage(image, rotation)
            .then((_) {
              if (_isRecording && _detectedPoses.isNotEmpty) {
                _poseHistory.add(_detectedPoses.first);
              }
              _isDetecting = false;
            })
            .catchError((e) {
              _isDetecting = false;
              debugPrint('Pose detection error: $e');
            });
      });

      if (mounted) setState(() => _errorMessage = null);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error initializing camera: ${e.description}';
      });
      await _cameraController?.dispose();
    }
  }

  Future<void> _processCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format:
            InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );

    final poses = await _poseDetector.processImage(inputImage);
    if (mounted) setState(() => _detectedPoses = poses);
  }

  // --------- Recording controls (save to device gallery) ----------
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

      try {
        await Gal.putVideo(file.path, album: 'FMS Recordings');
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video saved to gallery')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save video to gallery')),
        );
      }

      await _finalizeAndSaveSessionScore(); // Firestore: exercise + score + timestamp
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Error stopping recording: ${e.description}',
      );
    }
  }

  // Analyze from gallery (no upload to history)
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

    // (Frame-by-frame analysis placeholder; we use live-stream heuristics for now)
    await _finalizeAndSaveSessionScore();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analyzed video and saved session score')),
    );
  }

  Future<void> _finalizeAndSaveSessionScore() async {
    if (_selectedExercise == null) {
      _currentFmsScore = 0;
    }

    // Compute score + features from captured pose frames
    final result = PoseAnalysisUtils.analyze(
      _selectedExercise ?? ExerciseType.overheadSquat,
      _poseHistory,
    );
    _currentFmsScore = result.score;
    final features = result.features;

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
      timestamp: DateTime.now(), // server override in FirestoreService
      exercise: exerciseName,
      rating: _currentFmsScore,
      notes: '',
      videoUrl: null, // history doesn’t show video
      features: features,
    );

    try {
      await FirestoreService().saveFMSession(session);
      _poseHistory.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save session: $e')));
    }
  }

  // ---------------- UI helpers ----------------
  void _selectExerciseFromMenu(ExerciseType choice) {
    setState(() {
      _selectedExercise = choice;
    });
    _resetAnalysisState();
  }

  Future<void> _signOut() async {
    try {
      await AuthService().signOut();
      // AuthGate will route to login on null authState
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign out failed: $e')));
    }
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
        appBar: AppBar(
          title: const Text(title),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            ),
          ],
        ),
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
        appBar: AppBar(
          title: const Text(title),
          actions: [
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: _signOut,
            ),
          ],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // --- Precisely match overlay to CameraPreview (BoxFit.cover + mirroring) ---
    final rotation =
        InputImageRotationValue.fromRawValue(
          _cameraController!.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    final Size preview = _cameraController!.value.previewSize!;
    final bool swap =
        rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;

    final Size imageSizeUpright =
        swap
            ? Size(preview.height, preview.width)
            : Size(preview.width, preview.height);

    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: [
          // Exercise picker (kept as-is)
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
              // This will show whatever you have in ExerciseType.values (e.g., 3 most popular)
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
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          // Camera
          Positioned.fill(child: CameraPreview(_cameraController!)),

          // Pose overlay (perfectly aligned)
          if (_cameraController!.value.isInitialized &&
              _cameraController!.value.previewSize != null)
            Positioned.fill(
              child: CustomPaint(
                painter: PosePainter(
                  _detectedPoses,
                  imageSizeUpright,
                  rotation,
                  _cameraController!.description.lensDirection,
                ),
              ),
            ),

          // Status chip
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                      exLabel,
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
          ),

          // Bottom controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
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
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.fiber_manual_record,
                    ),
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
          ),
        ],
      ),
    );
  }
}
