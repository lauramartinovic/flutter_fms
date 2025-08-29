// lib/screens/fms_capture/fms_capture_screen.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // For recording
import 'package:image_picker/image_picker.dart'; // For picking from gallery
import 'package:flutter_fms/services/storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_fms/services/firestore_service.dart';
import 'package:flutter_fms/models/fms_session_model.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:flutter/foundation.dart'; // For WriteBuffer
import 'package:flutter_fms/widgets/pose_painter.dart'; // Import the PosePainter

// You'll need to pass the list of available cameras to this screen
// This list is usually retrieved once when your app starts (e.g., in main.dart)
// and then passed down.
class FMSCaptureScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FMSCaptureScreen({super.key, required this.cameras});

  @override
  State<FMSCaptureScreen> createState() => _FMSCaptureScreenState();
}

class _FMSCaptureScreenState extends State<FMSCaptureScreen> {
  CameraController? _cameraController;
  bool _isRecording = false;
  XFile? _capturedVideo; // To store the recorded or picked video file
  String? _errorMessage;

  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(),
  );
  bool _isDetecting =
      false; // Flag to prevent multiple detections on same frame
  List<Pose> _detectedPoses = []; // To store detected poses

  @override
  void initState() {
    super.initState();
    // Initialize the camera when the screen loads, if cameras are available
    if (widget.cameras.isNotEmpty) {
      _initializeCamera(
        widget.cameras[0],
      ); // Use the first available camera (usually back)
    } else {
      _errorMessage = 'No cameras found on this device.';
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose(); // Dispose camera controller
    _poseDetector.close(); // Dispose pose detector
    super.dispose();
  }

  // --- Camera Initialization and Control ---
  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    // Dispose previous controller if it exists
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }

    _cameraController = CameraController(
      cameraDescription,
      ResolutionPreset.medium, // Adjust resolution as needed
      enableAudio: true,
      imageFormatGroup:
          ImageFormatGroup.yuv420, // Recommended for ML processing later
    );

    try {
      await _cameraController!.initialize();
      if (!mounted) return; // Check if the widget is still in the tree

      // Start the image stream for live pose detection
      // Note: Processing frames and recording video simultaneously can be
      // very demanding on device performance. Monitor carefully.
      _cameraController!.startImageStream((CameraImage image) {
        if (!_isDetecting) {
          _isDetecting = true;
          // Determine the correct InputImageRotation from sensorOrientation
          final InputImageRotation imageRotation =
              InputImageRotationValue.fromRawValue(
                _cameraController!.description.sensorOrientation,
              ) ??
              InputImageRotation.rotation0deg; // Default if value is unexpected

          _processCameraImage(image, imageRotation)
              .then((_) {
                _isDetecting = false;
              })
              .catchError((error) {
                _isDetecting = false;
                // Use debugPrint or a logger in production
                debugPrint('Pose detection error: $error');
              });
        }
      });

      setState(() {
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error initializing camera: ${e.description}';
      });
      _cameraController?.dispose();
    }
  }

  // --- ML Kit Pose Detection Logic ---
  // Updated to use InputImageMetadata (new API in google_mlkit_commons >=0.11.0)
  Future<void> _processCameraImage(
    CameraImage image,
    InputImageRotation imageRotation,
  ) async {
    // Collect all bytes from planes
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // Use new InputImageMetadata (replaces InputImageData + InputImagePlaneMetadata)
    final inputImage = InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format:
            InputImageFormatValue.fromRawValue(image.format.raw) ??
            InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );

    // Perform pose detection
    final List<Pose> poses = await _poseDetector.processImage(inputImage);

    if (mounted) {
      setState(() {
        _detectedPoses = poses;
      });
    }
  }

  // --- Start Recording Video ---
  Future<void> _startVideoRecording() async {
    // You might want to stop the image stream for detection during recording to save resources
    // await _cameraController!.stopImageStream();
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _errorMessage = 'Camera not initialized.');
      return;
    }
    if (_cameraController!.value.isRecordingVideo) {
      // Already recording
      return;
    }

    try {
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

  // --- Stop Recording Video ---
  Future<void> _stopVideoRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isRecordingVideo) {
      return;
    }

    try {
      final XFile file = await _cameraController!.stopVideoRecording();
      // Resume image stream for detection after recording stops
      // _cameraController!.startImageStream((image) => _processCameraImage(image, _cameraController!.description.sensorOrientation));
      if (!mounted) return;
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

  // --- Pick Video from Gallery ---
  Future<void> _pickVideoFromGallery() async {
    // You might want to stop the image stream for detection when picking from gallery
    // await _cameraController!.stopImageStream();
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      // Resume image stream for detection after picking from gallery
      // _cameraController!.startImageStream((image) => _processCameraImage(image, _cameraController!.description.sensorOrientation));
      if (!mounted) return;
      if (video != null) {
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

  // --- Display Preview and Upload Option ---
  void _showVideoPreviewAndUploadOption(XFile videoFile) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Video Captured/Selected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('File Path: ${videoFile.path.split('/').last}'),
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
                },
                child: const Text('Retake/Reselect'),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Actual Video Upload Logic ---
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
          content: Text(
            'Uploading video: ${videoFile.path.split('/').last}...',
          ),
        ),
      );

      final StorageService storageService = StorageService();
      final String downloadUrl = await storageService.uploadFMSVideo(
        videoFile,
        currentUser.uid,
        sessionTimestamp: DateTime.now(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video uploaded successfully! URL: $downloadUrl'),
        ),
      );

      // --- Save FMS Session data to Cloud Firestore ---
      final FirestoreService firestoreService = FirestoreService();
      final FMSSessionModel newSession = FMSSessionModel(
        userId: currentUser.uid,
        timestamp: DateTime.now(),
        videoUrl: downloadUrl,
        rating: 'Pending',
        notes: 'Recorded via app',
      );

      final String sessionId = await firestoreService.saveFMSession(newSession);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session data saved to Firestore with ID: $sessionId'),
        ),
      );

      setState(() {
        _capturedVideo = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Operation failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('FMS Capture')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      // Show loading or options if camera is not ready or no cameras available
      return Scaffold(
        appBar: AppBar(title: const Text('FMS Capture')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('Initializing camera or loading options...'),
              const SizedBox(height: 30),
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

    // Main camera preview and controls
    return Scaffold(
      appBar: AppBar(title: const Text('FMS Capture')),
      body: Stack(
        children: [
          // Camera Preview (as large as possible)
          Positioned.fill(child: CameraPreview(_cameraController!)),

          // NEW: Pose detection overlay
          // Only show if camera is initialized and has a preview size
          if (_cameraController!.value.isInitialized &&
              _cameraController!.value.previewSize != null)
            Positioned.fill(
              child: CustomPaint(
                painter: PosePainter(
                  _detectedPoses,
                  // Use preview size for painting.
                  // Note: previewSize can be null before initialization, hence the check.
                  _cameraController!.value.previewSize!,
                  // Pass InputImageRotation to painter, as it expects that type
                  // You need to correctly convert the sensorOrientation to InputImageRotation
                  // before passing it to the painter, as PosePainter expects InputImageRotation.
                  // The camera's sensorOrientation (int) is what you typically get.
                  // Let's ensure the painter's constructor handles this or pass it correctly.
                  // Correction: PosePainter expects InputImageRotation, so we convert it here.
                  InputImageRotationValue.fromRawValue(
                        _cameraController!.description.sensorOrientation,
                      ) ??
                      InputImageRotation.rotation0deg,
                  _cameraController!.description.lensDirection,
                ),
              ),
            ),

          // Controls at the bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(20.0),
              color: Colors.black54, // Semi-transparent background for controls
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Button to start/stop recording
                  FloatingActionButton(
                    onPressed:
                        _isRecording
                            ? _stopVideoRecording
                            : _startVideoRecording,
                    backgroundColor: _isRecording ? Colors.red : Colors.blue,
                    child: Icon(_isRecording ? Icons.stop : Icons.videocam),
                  ),
                  const SizedBox(width: 20),
                  // Button to pick from gallery
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
