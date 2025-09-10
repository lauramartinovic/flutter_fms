// lib/screens/fms_capture/fms_capture_screen.dart

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';
import 'dart:io';

import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/widgets/pose_painter.dart';
import 'package:flutter_fms/utils/pose_analysis_utils.dart';
import 'package:flutter_fms/screens/home/edit_profile_screen.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_thumbnail/video_thumbnail.dart'
    as video_thumbnail_package;

class FMSCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FMSCaptureScreen({super.key, required this.cameras});

  @override
  State<FMSCaptureScreen> createState() => _FMSCaptureScreenState();
}

class _FMSCaptureScreenState extends State<FMSCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isRecording = false;
  String? _errorMessage;

  // Pose state
  ExerciseType? _selectedExercise;
  int _currentFmsScore = 0;
  final List<Pose> _poseHistory = [];
  List<Pose> _detectedPoses = [];

  // ML Kit detector (STREAM mode -> faster live preview)
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.base,
    ),
  );

  // --- Live stream while recording: decoupled push/pull ---
  CameraImage? _latestImage; // latest frame buffer (overwrites older)
  bool _mlBusy = false; // prevents re-entrancy in ML loop
  Timer? _mlTicker; // periodic pull loop timer
  InputImageRotation _cachedRotation = InputImageRotation.rotation0deg;

  // sample fewer frames to history for scoring (every 3rd processed frame)
  int _historySampleModulo = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.cameras.isNotEmpty) {
      _initializeCamera(widget.cameras[0]);
    } else {
      _errorMessage = 'No cameras found on this device.';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _mlTicker?.cancel();
    () async {
      if (_cameraController?.value.isStreamingImages == true) {
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {}
      }
    }();

    _poseDetector.close();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _mlTicker?.cancel();
      () async {
        if (controller.value.isStreamingImages) {
          try {
            await controller.stopImageStream();
          } catch (_) {}
        }
        await controller.dispose();
      }();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(controller.description);
    }
  }

  void _resetAnalysisState() {
    _poseHistory.clear();
    _currentFmsScore = 0;
    _historySampleModulo = 0;
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

      // Cache rotation (sensorOrientation is fixed per session)
      _cachedRotation =
          InputImageRotationValue.fromRawValue(
            _cameraController!.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg;

      // Start ultra-light PUSH stream: store only latest frame
      await _cameraController!.startImageStream((CameraImage image) {
        _latestImage = image; // overwrite old frame; no heavy work here
      });

      // Start periodic PULL loop (10–15 Hz is enough for pose)
      _mlTicker?.cancel();
      _mlTicker = Timer.periodic(const Duration(milliseconds: 70), (_) {
        _processLatestFrameIfAny();
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

  // Periodic ML loop — processes at most one frame at a time
  Future<void> _processLatestFrameIfAny() async {
    if (_mlBusy) return;
    final frame = _latestImage;
    if (frame == null) return;

    _mlBusy = true;
    // clear buffer early so new frames can arrive during processing
    _latestImage = null;

    try {
      final input = _toInputImage(frame, _cachedRotation);
      final poses = await _poseDetector.processImage(input);
      if (!mounted) return;
      setState(() => _detectedPoses = poses);

      // sample to history during recording (every 3rd processed frame)
      if (_isRecording && poses.isNotEmpty) {
        _historySampleModulo = (_historySampleModulo + 1) % 3;
        if (_historySampleModulo == 0) {
          _poseHistory.add(poses.first);
        }
      }
    } catch (e, st) {
      debugPrint('processLatestFrame error: $e$st');
    } finally {
      _mlBusy = false;
    }
  }

  // Convert CameraImage → InputImage (Android NV21 / iOS BGRA8888)
  InputImage _toInputImage(CameraImage image, InputImageRotation rotation) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (image.planes.isEmpty) {
        // Guard against unexpected buffers
        throw StateError('No planes in CameraImage');
      }

      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21, // ML Kit prefers NV21 on Android
          bytesPerRow: image.planes.first.bytesPerRow, // Y plane stride
        ),
      );
    } else {
      // iOS: BGRA8888 single plane
      final bytes = image.planes.first.bytes;
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    }
  }

  // --------- Recording controls (save only to device gallery) ----------
  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _errorMessage = 'Camera not initialized.');
      return;
    }
    if (_selectedExercise == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an exercise first.')),
      );
      return;
    }
    if (_cameraController!.value.isRecordingVideo) return;

    try {
      _resetAnalysisState();

      // Keep the image stream running on Android while we record
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
        final has = await (Gal.hasAccess(toAlbum: true) ?? Future.value(false));
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

      // After recording, compute features and save session
      await _finalizeAndSaveSessionScore();
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Error stopping recording: ${e.description}',
      );
    }
  }

  Future<void> _analyzeVideoFromGallery() async {
    if (_selectedExercise == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an exercise first.')),
      );
      return;
    }

    final picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    try {
      // 1) Probe duration with video_player
      final controller = VideoPlayerController.file(File(video.path));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();

      // 2) Extract frames at ~2 fps (adjust if you want)
      const framesPerSecond = 2;
      final frameStep = Duration(
        milliseconds: (1000 / framesPerSecond).round(),
      );
      final totalMs = duration.inMilliseconds;

      // Reset state so we only use frames from the picked video
      _poseHistory.clear();

      for (int t = 0; t < totalMs; t += frameStep.inMilliseconds) {
        // 3) Make a frame image (thumbnail) at timestamp t
        final String? framePath = await video_thumbnail_package
            .VideoThumbnail.thumbnailFile(
          video: video.path,
          timeMs: t,
          imageFormat: video_thumbnail_package.ImageFormat.JPEG,
          quality: 80,
        );

        if (framePath == null) continue;

        try {
          // 4) Run ML Kit pose on that frame
          final input = InputImage.fromFilePath(framePath);
          final poses = await _poseDetector.processImage(input);

          if (poses.isNotEmpty) {
            // sample roughly every frame (you can downsample if needed)
            _poseHistory.add(poses.first);
          }
        } catch (e) {
          debugPrint('Gallery frame $t ms failed: $e');
        }
      }

      // 5) Compute features/score and save session (now _poseHistory is filled)
      await _finalizeAndSaveSessionScore();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analyzed video and saved session score')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed analyzing video: $e')));
    }
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
      if (!mounted) return;
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

      // Save features to that session document
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

    final exLabel =
        _selectedExercise == null
            ? 'Select exercise'
            : (exerciseNames[_selectedExercise!] ??
                _selectedExercise.toString());

    // Use cached rotation for the painter
    final rotation = _cachedRotation;

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
          final preview = _cameraController!.value.previewSize!;
          final bool isRot90or270 =
              rotation == InputImageRotation.rotation90deg ||
              rotation == InputImageRotation.rotation270deg;

          // Camera image logical size for painter
          final Size imageSize =
              isRot90or270
                  ? Size(preview.height, preview.width)
                  : Size(preview.width, preview.height);

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
    );
  }
}
