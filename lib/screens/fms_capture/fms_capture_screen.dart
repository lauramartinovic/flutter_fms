import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // WriteBuffer
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:gallery_saver/gallery_saver.dart';

import 'package:flutter_fms/services/storage_service.dart';
import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:flutter_fms/widgets/pose_painter.dart';
import 'package:flutter_fms/utils/pose_analysis_utils.dart';

class FMSCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FMSCaptureScreen({super.key, required this.cameras});

  @override
  State<FMSCaptureScreen> createState() => _FMSCaptureScreenState();
}

class _FMSCaptureScreenState extends State<FMSCaptureScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  XFile? _capturedVideo;
  String? _errorMessage;

  // Exercise selection + scoring
  ExerciseType? _selectedExercise;
  int _currentFmsScore = 0;
  final List<Pose> _poseHistory = [];

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(),
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
        enableAudio: true,
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
                // Store one pose per frame for later scoring
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

  // New commons API (InputImageMetadata)
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

  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _errorMessage = 'Camera not initialized.');
      return;
    }
    if (_selectedExercise == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an exercise first.')),
      );
      return;
    }
    if (_cameraController!.value.isRecordingVideo) return;

    try {
      _resetAnalysisState();
      await _cameraController!.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = 'Error starting video recording: ${e.description}',
      );
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo)
      return;

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      if (!mounted) return;

      // Compute score from collected frames
      if (_selectedExercise != null) {
        _currentFmsScore = PoseAnalysisUtils.scoreExercise(
          _selectedExercise!,
          _poseHistory,
        );
      } else {
        _currentFmsScore = 0;
      }

      // Save to gallery (optional)
      final ok = await GallerySaver.saveVideo(
        file.path,
        albumName: 'FMS Recordings',
      );
      debugPrint(
        ok == true
            ? 'Video saved to gallery'
            : 'Failed to save video to gallery',
      );

      setState(() {
        _isRecording = false;
        _capturedVideo = file;
        _errorMessage = null;
      });

      _showVideoPreviewAndUploadOption(file);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _errorMessage = 'Error stopping video recording: ${e.description}',
      );
    }
  }

  Future<void> _pickVideoFromGallery() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted) return;

      if (video != null) {
        // NOTE: we did not collect pose frames for gallery videos.
        // You can mark these as "Pending" score or run an offline analysis pipeline.
        _currentFmsScore = 0;
        setState(() {
          _capturedVideo = video;
          _errorMessage = null;
        });
        _showVideoPreviewAndUploadOption(video);
      } else {
        setState(() => _errorMessage = 'No video selected.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Error picking video: $e');
    }
  }

  void _showVideoPreviewAndUploadOption(XFile videoFile) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Video Captured/Selected'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('File: ${videoFile.path.split('/').last}'),
                const SizedBox(height: 8),
                if (_selectedExercise != null)
                  Text('Exercise: ${exerciseNames[_selectedExercise!]!}'),
                Text('Score: $_currentFmsScore'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _uploadVideo(videoFile);
                  },
                  child: const Text('Upload Video'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _capturedVideo = null;
                    });
                    _resetAnalysisState();
                  },
                  child: const Text('Retake/Reselect'),
                ),
              ],
            ),
          ),
    );
  }

  Future<void> _uploadVideo(XFile videoFile) async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: No user logged in for upload.')),
      );
      return;
    }

    try {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uploading ${videoFile.path.split('/').last}...'),
        ),
      );

      final storageService = StorageService();
      final url = await storageService.uploadFMSVideo(
        videoFile,
        currentUser.uid,
        sessionTimestamp: DateTime.now(),
      );

      final firestoreService = FirestoreService();

      final exerciseName =
          _selectedExercise != null
              ? (exerciseNames[_selectedExercise!] ??
                  _selectedExercise.toString())
              : 'Unknown';

      final session = FMSSessionModel(
        userId: currentUser.uid,
        timestamp: DateTime.now(),
        videoUrl: url,
        exercise: exerciseName,
        rating: _currentFmsScore,
        notes: 'Recorded via app',
      );

      final sessionId = await firestoreService.saveFMSession(session);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved! Session ID: $sessionId')));

      setState(() {
        _capturedVideo = null;
      });
      _resetAnalysisState();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Operation failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Top errors
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('FMS Capture')),
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
        appBar: AppBar(title: const Text('FMS Capture')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Initializing camera...'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _pickVideoFromGallery,
                icon: const Icon(Icons.photo_library),
                label: const Text('Choose Existing Video'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('FMS Capture'),
        actions: [
          // Exercise selector
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ExerciseType>(
                value: _selectedExercise,
                hint: const Text(
                  'Select exercise',
                  style: TextStyle(color: Colors.white),
                ),
                dropdownColor: Colors.blueGrey.shade700,
                iconEnabledColor: Colors.white,
                onChanged: (ExerciseType? ex) {
                  setState(() {
                    _selectedExercise = ex;
                  });
                  _resetAnalysisState();
                },
                items:
                    ExerciseType.values.map((e) {
                      return DropdownMenuItem(
                        value: e,
                        child: Text(exerciseNames[e] ?? e.toString()),
                      );
                    }).toList(),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_cameraController!)),
          if (_cameraController!.value.isInitialized &&
              _cameraController!.value.previewSize != null)
            Positioned.fill(
              child: CustomPaint(
                painter: PosePainter(
                  _detectedPoses,
                  _cameraController!.value.previewSize!,
                  InputImageRotationValue.fromRawValue(
                        _cameraController!.description.sensorOrientation,
                      ) ??
                      InputImageRotation.rotation0deg,
                  _cameraController!.description.lensDirection,
                ),
              ),
            ),
          // Controls
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black54,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    onPressed:
                        _isRecording
                            ? _stopVideoRecording
                            : _startVideoRecording,
                    backgroundColor: _isRecording ? Colors.red : Colors.blue,
                    child: Icon(_isRecording ? Icons.stop : Icons.videocam),
                  ),
                  FloatingActionButton(
                    onPressed: _pickVideoFromGallery,
                    backgroundColor: Colors.green,
                    child: const Icon(Icons.photo_library),
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
