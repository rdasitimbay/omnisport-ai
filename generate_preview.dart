import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final foregroundFile = File('assets/images/android_foreground.png');
  final foreground = img.decodeImage(foregroundFile.readAsBytesSync())!;

  // The adaptive icon mask on most launchers cuts it to a circle.
  // We'll create a 1080x1080 canvas (10x 108dp)
  int size = 1080;
  final canvas = img.Image(width: size, height: size);
  
  // Fill transparent initially
  // Draw a circle of #0A192F (R:10 G:25 B:47)
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      double dx = x - size / 2.0;
      double dy = y - size / 2.0;
      if ((dx * dx + dy * dy) <= (size * size / 4.0)) {
        canvas.setPixel(x, y, img.ColorRgb8(10, 25, 47));
      } else {
        canvas.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0)); // Transparent outside mask
      }
    }
  }

  // Scale the foreground to match the 1080 canvas 
  // (The foreground script already perfectly framed it to the 65% area proportionally)
  final scaledForeground = img.copyResize(foreground, width: size, height: size, interpolation: img.Interpolation.linear);

  // Composite the foreground over the circle mask
  // Pixels from scaledForeground should only be drawn if they have alpha over the circle
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      double dx = x - size / 2.0;
      double dy = y - size / 2.0;
      // Only draw inside the mask
      if ((dx * dx + dy * dy) <= (size * size / 4.0)) {
        final fgPixel = scaledForeground.getPixel(x, y);
        if (fgPixel.a > 0) {
          // Standard alpha blending
          final double alpha = fgPixel.a / 255.0;
          final int bgR = 10;
          final int bgG = 25;
          final int bgB = 47;
          
          final int r = ((fgPixel.r * alpha) + (bgR * (1 - alpha))).toInt();
          final int g = ((fgPixel.g * alpha) + (bgG * (1 - alpha))).toInt();
          final int b = ((fgPixel.b * alpha) + (bgB * (1 - alpha))).toInt();
          
          canvas.setPixel(x, y, img.ColorRgb8(r, g, b));
        }
      }
    }
  }

  // Save the preview to the artifacts directory so the agent can embed it in walkthrough
  final previewFile = File('android_icon_preview.png');
  previewFile.writeAsBytesSync(img.encodePng(canvas));
  print('Successfully generated android_icon_preview.png simulator screenshot.');
}
