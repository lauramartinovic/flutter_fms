//lib/screens/fms_capture/fms_capture_screen.dart

import 'package:flutter/material.dart';
import 'package:camera/camera.dart'; // For recording
import 'package:image_picker/image_picker.dart'; // For picking from gallery
import 'package:flutter_fms/services/storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Already there
import 'package:flutter_fms/services/firestore_service.dart'; // <--- ADD THIS IMPORT
import 'package:flutter_fms/models/fms_session_model.dart'; // <--- ADD THIS IMPORT

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
      setState(() {
        _errorMessage = null; // Clear any previous errors
      });
    } on CameraException catch (e) {
      if (!mounted) return; // Check if the widget is still in the tree
      setState(() {
        _errorMessage = 'Error initializing camera: ${e.description}';
      });
      _cameraController?.dispose();
    }
  }

  // --- Start Recording Video ---
  Future<void> _startVideoRecording() async {
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
      if (!mounted) return; // Check if the widget is still in the tree
      setState(() {
        _isRecording = true;
        _errorMessage = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return; // Check if the widget is still in the tree
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
      if (!mounted) return; // Check if the widget is still in the tree
      setState(() {
        _isRecording = false;
        _capturedVideo = file;
        _errorMessage = null;
      });
      // Now _capturedVideo holds the recorded file, ready for upload!
      _showVideoPreviewAndUploadOption(file);
    } on CameraException catch (e) {
      if (!mounted) return; // Check if the widget is still in the tree
      setState(
        () =>
            _errorMessage = 'Error stopping video recording: ${e.description}',
      );
    }
  }

  // --- Pick Video from Gallery ---
  Future<void> _pickVideoFromGallery() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
      if (!mounted) return; // Check if the widget is still in the tree
      if (video != null) {
        setState(() {
          _capturedVideo = video;
          _errorMessage = null;
        });
        // Now _capturedVideo holds the picked file, ready for upload!
        _showVideoPreviewAndUploadOption(video);
      } else {
        setState(() => _errorMessage = 'No video selected.');
      }
    } catch (e) {
      if (!mounted) return; // Check if the widget is still in the tree
      setState(() => _errorMessage = 'Error picking video: $e');
    }
  }

  // --- Display Preview and Upload Option ---
  void _showVideoPreviewAndUploadOption(XFile videoFile) {
    if (!mounted) return; // Important check before using context after async
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Video Captured/Selected'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // You might want to use a video player package here
              // For now, just show confirmation or details
              Text('File Path: ${videoFile.path.split('/').last}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  // TODO: Call your storage_service to upload the videoFile
                  _uploadVideo(videoFile);
                },
                child: const Text('Upload Video'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  setState(() {
                    _capturedVideo =
                        null; // Clear video to allow re-capture/re-select
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

  // --- Actual Video Upload Logic (REPLACE YOUR CURRENT _uploadVideo WITH THIS) ---
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

      // --- NEW: Save FMS Session data to Cloud Firestore ---

      final FirestoreService firestoreService = FirestoreService();

      final FMSSessionModel newSession = FMSSessionModel(
        userId: currentUser.uid,

        timestamp:
            DateTime.now(), // Local timestamp, Firestore will use server timestamp if FieldValue.serverTimestamp() is used

        videoUrl: downloadUrl,

        rating: 'Pending', // Initial status, will be updated by ML/manual input

        notes: 'Recorded via app',
      );

      final String sessionId = await firestoreService.saveFMSession(newSession);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session data saved to Firestore with ID: $sessionId'),
        ),
      );

      // --- END NEW ---

      setState(() {
        _capturedVideo =
            null; // Clear captured video after successful upload and save
      });

      // Optionally navigate to history screen or clear form
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Operation failed: $e')));
    }
  }

  // ... (rest of your _FMSCaptureScreenState and build method)

  @override
  void dispose() {
    _cameraController?.dispose(); // Dispose camera controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FIXED: Corrected method signature here
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
