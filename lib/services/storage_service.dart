// lib/services/storage_service.dart

import 'dart:io'; // Required for File class
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart'; // For XFile

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads an FMS video to Cloud Storage for Firebase.
  ///
  /// [videoFile]: The XFile object representing the video to upload (from camera or gallery).
  /// [userId]: The ID of the user uploading the video (e.g., Firebase Auth UID).
  /// [sessionTimestamp]: Optional timestamp to make the filename unique and ordered.
  ///
  /// Returns the download URL of the uploaded video.
  Future<String> uploadFMSVideo(
    XFile videoFile,
    String userId, {
    DateTime? sessionTimestamp,
  }) async {
    try {
      // 1. Create a unique path for the video
      // Using userId for user-specific folders
      // Using a timestamp for unique filenames and easy ordering
      final String fileName =
          '${sessionTimestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}.mp4';
      final String path =
          'fms_videos/$userId/$fileName'; // Example: fms_videos/user123/1678886400000.mp4

      // 2. Get a reference to the storage location
      final Reference storageRef = _storage.ref().child(path);

      // 3. Upload the file
      // Convert XFile to dart:io.File as putFile expects a File object
      final UploadTask uploadTask = storageRef.putFile(File(videoFile.path));

      // 4. Wait for the upload to complete and get metadata
      final TaskSnapshot snapshot = await uploadTask;

      // 5. Get the download URL
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      print('Video uploaded successfully! Download URL: $downloadUrl');
      return downloadUrl;
    } on FirebaseException catch (e) {
      // Handle Firebase Storage specific errors
      print('Firebase Storage Error: ${e.code} - ${e.message}');
      throw 'Failed to upload video: ${e.message ?? e.code}';
    } catch (e) {
      // Handle any other unexpected errors
      print('General Upload Error: $e');
      throw 'An unexpected error occurred during upload: $e';
    }
  }

  // You can add other methods here, e.g., to delete videos, get file metadata etc.
}
