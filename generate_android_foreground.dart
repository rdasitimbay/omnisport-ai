import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final logoFile = File('assets/images/app_logo_shield_premium_fin.png');
  final original = img.decodeImage(logoFile.readAsBytesSync());

  if (original == null) {
    print('Failed to decode image');
    return;
  }

  // Find bounding box to remove transparent padding
  int minX = original.width;
  int minY = original.height;
  int maxX = 0;
  int maxY = 0;

  for (int y = 0; y < original.height; y++) {
    for (int x = 0; x < original.width; x++) {
      final pixel = original.getPixel(x, y);
      if (pixel.a > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  final croppedWidth = maxX - minX + 1;
  final croppedHeight = maxY - minY + 1;
  
  // Crop the image
  final cropped = img.copyCrop(original, x: minX, y: minY, width: croppedWidth, height: croppedHeight);

  // The shield must occupy exactly 65% of the Adaptive Icon Canvas
  // This translates to canvas_size = max(croppedWidth, croppedHeight) / 0.65;
  final int maxDim = math.max(croppedWidth, croppedHeight);
  final int canvasSize = (maxDim / 0.65).toInt();

  final canvas = img.Image(width: canvasSize, height: canvasSize);
  // Do not fill background! Adaptive Icon Foreground must be transparent PNG!

  final dstX = (canvasSize - croppedWidth) ~/ 2;
  final dstY = (canvasSize - croppedHeight) ~/ 2;

  img.compositeImage(canvas, cropped, dstX: dstX, dstY: dstY);

  File('assets/images/android_foreground.png').writeAsBytesSync(img.encodePng(canvas));
  print('Successfully generated android_foreground.png bounded exactly to 65% safe area.');
}
