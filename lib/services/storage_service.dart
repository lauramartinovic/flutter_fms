import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadFMSVideo(
    XFile videoFile,
    String userId, {
    DateTime? sessionTimestamp,
  }) async {
    try {
      final String fileName =
          '${(sessionTimestamp ?? DateTime.now()).millisecondsSinceEpoch}.mp4';
      final String path = 'fms_videos/$userId/$fileName';

      final ref = _storage.ref(path);

      // Optional: Set metadata contentType for nicer handling
      final metadata = SettableMetadata(contentType: 'video/mp4');

      final UploadTask task = ref.putFile(File(videoFile.path), metadata);
      final TaskSnapshot snap = await task;
      final String url = await snap.ref.getDownloadURL();
      return url;
    } on FirebaseException catch (e) {
      throw Exception('Firebase Storage Error: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Upload failed: $e');
    }
  }
}
