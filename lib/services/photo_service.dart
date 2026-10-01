import 'package:image_picker/image_picker.dart';
import 'dart:io';

class PhotoService {
  static final ImagePicker _picker = ImagePicker();

  // Pick single photo
  static Future<File?> pickSinglePhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );

      if (image != null) {
        return File(image.path);
      }
    } catch (e) {
      print('Error picking image: $e');
    }
    return null;
  }

  // Pick multiple photos
  static Future<List<File>> pickMultiplePhotos() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        imageQuality: 100,
      );

      return images.map((image) => File(image.path)).toList();
    } catch (e) {
      print('Error picking images: $e');
    }
    return [];
  }
}