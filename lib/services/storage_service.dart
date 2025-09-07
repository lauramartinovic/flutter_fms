import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Compresses the picked/taken video to a low-res variant and uploads it.
  /// Returns the download URL.
  Future<String> uploadLowResVideo(
    XFile input,
    String userId, {
    DateTime? sessionTimestamp,
    // target bitrate/quality knobs:
    VideoQuality quality = VideoQuality.MediumQuality, // ~540p-ish
  }) async {
    MediaInfo? info;
    try {
      // 1) Compress to low-res
      info = await VideoCompress.compressVideo(
        input.path,
        quality: quality,
        deleteOrigin: false, // keep original file
        includeAudio: true,
      );

      final File uploadFile = File((info?.path ?? input.path));

      // 2) Build a Storage path
      final String fileName =
          '${(sessionTimestamp ?? DateTime.now()).millisecondsSinceEpoch}.mp4';
      final String path = 'fms_videos_lowres/$userId/$fileName';

      // 3) Upload with contentType
      final ref = _storage.ref(path);
      final metadata = SettableMetadata(contentType: 'video/mp4');

      final UploadTask task = ref.putFile(uploadFile, metadata);
      final TaskSnapshot snap = await task;
      return await snap.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw Exception('Firebase Storage Error: ${e.code} - ${e.message}');
    } catch (e) {
      throw Exception('Low-res upload failed: $e');
    } finally {
      // iOS/Android temp file cleanup (if any)
      if (info != null) {
        await VideoCompress.deleteAllCache();
      }
    }
  }
}
