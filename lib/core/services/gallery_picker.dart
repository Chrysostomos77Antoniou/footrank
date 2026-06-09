import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Picks an image from the device gallery.
///
/// On Android we use a native `ACTION_PICK` intent so the **gallery** opens
/// directly (the system Photo Picker isn't available on every device, and
/// image_picker otherwise falls back to the file browser). On other platforms
/// we use the standard image_picker gallery source.
class GalleryPicker {
  static const _channel = MethodChannel('footrank/gallery');

  static Future<({Uint8List bytes, String ext})?> pick() async {
    if (!kIsWeb && Platform.isAndroid) {
      final path =
          await _channel.invokeMethod<String>('pickImageFromGallery');
      if (path == null) return null; // cancelled
      final bytes = await File(path).readAsBytes();
      return (bytes: bytes, ext: 'jpg');
    }

    // iOS / other: standard picker, downscaled.
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    return (bytes: bytes, ext: ext);
  }
}
