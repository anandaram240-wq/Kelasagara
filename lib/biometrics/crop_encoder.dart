import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Lossless PNG of the aligned 112x112 crop. The server decodes this and feeds
/// the model, so the bytes must not be re-compressed lossily.
Uint8List rgb112ToPng(Uint8List rgb) {
  assert(rgb.length == 112 * 112 * 3);
  final image = img.Image.fromBytes(width: 112, height: 112, bytes: rgb.buffer, numChannels: 3);
  return Uint8List.fromList(img.encodePng(image, level: 6));
}

/// Larger upright colour image for the server's OFIQ and liveness checks.
/// Keep it under the server limit (2,000,000 bytes); quality 90 at 480x600 is ~100-200 KB.
Uint8List rgbToJpeg(Uint8List rgb, int w, int h, {int quality = 90}) {
  final image = img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3);
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// Small greyscale frame for the active-challenge check (160x160, quality 70).
Uint8List lumaToJpeg(Uint8List luma, int n, {int quality = 70}) {
  final image = img.Image.fromBytes(width: n, height: n, bytes: luma.buffer, numChannels: 1);
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}
