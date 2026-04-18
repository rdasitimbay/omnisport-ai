import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final logoFile = File('assets/images/logo_app_os_ai_pure.png');
  final original = img.decodeImage(logoFile.readAsBytesSync());

  if (original == null) {
    print('Failed to decode image');
    return;
  }

  // Find bounding box ignoring transparent pixels
  int minX = original.width;
  int minY = original.height;
  int maxX = 0;
  int maxY = 0;

  for (int y = 0; y < original.height; y++) {
    for (int x = 0; x < original.width; x++) {
      final pixel = original.getPixel(x, y);
      
      // If alpha is greater than zero, it's the pure shield!
      if (pixel.a > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  // Safety break if image was invisible
  if (maxX < minX || maxY < minY) {
    minX = 0; minY = 0;
    maxX = original.width - 1; maxY = original.height - 1;
  }

  final croppedWidth = maxX - minX + 1;
  final croppedHeight = maxY - minY + 1;
  final cropped = img.copyCrop(original, x: minX, y: minY, width: croppedWidth, height: croppedHeight);
  
  print('Original Size: ${original.width}x${original.height} | Cropped Size: ${croppedWidth}x${croppedHeight}');

  // ---- IOS GENERATION (Needs to fill up most of the 1:1 square, e.g., 80%) ----
  final int maxDimIOS = math.max(croppedWidth, croppedHeight);
  final int canvasSizeIOS = (maxDimIOS / 0.80).toInt(); // 80% coverage
  final canvasIOS = img.Image(width: canvasSizeIOS, height: canvasSizeIOS);
  img.fill(canvasIOS, color: img.ColorRgb8(10, 25, 47)); // Navy Blue
  final dstXIOS = (canvasSizeIOS - croppedWidth) ~/ 2;
  final dstYIOS = (canvasSizeIOS - croppedHeight) ~/ 2;
  img.compositeImage(canvasIOS, cropped, dstX: dstXIOS, dstY: dstYIOS);
  File('assets/images/ios_icon.png').writeAsBytesSync(img.encodePng(canvasIOS));
  print('iOS icon generated spanning 80% of canvas.');

  // ---- ANDROID FOREGROUND GENERATION (Needs to be smaller to fit in the 66% Mask) ----
  final int canvasSizeAndroid = (maxDimIOS / 0.65).toInt(); // 65% relative to 108dp
  final canvasAndroid = img.Image(width: canvasSizeAndroid, height: canvasSizeAndroid);
  // Transparent canvas for android foreground
  final dstXAndroid = (canvasSizeAndroid - croppedWidth) ~/ 2;
  final dstYAndroid = (canvasSizeAndroid - croppedHeight) ~/ 2;
  img.compositeImage(canvasAndroid, cropped, dstX: dstXAndroid, dstY: dstYAndroid);
  File('assets/images/android_foreground.png').writeAsBytesSync(img.encodePng(canvasAndroid));
  print('Android foreground generated spanning 60% of canvas.');
}
