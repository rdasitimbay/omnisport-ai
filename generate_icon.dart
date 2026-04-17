import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final logoFile = File('assets/images/app_logo_shield_premium.png');
  final original = img.decodeImage(logoFile.readAsBytesSync());

  if (original == null) {
    print('Failed to decode image');
    return;
  }

  // Calculate new size (125% -> image takes ~80% of canvas)
  final double scaleFactor = 1.25;
  final newWidth = (original.width * scaleFactor).toInt();
  final newHeight = (original.height * scaleFactor).toInt();

  // Create a solid Navy Blue background (#0A192F = R:10, G:25, B:47)
  final canvas = img.Image(width: newWidth, height: newHeight);
  img.fill(canvas, color: img.ColorRgb8(10, 25, 47));

  // Center the original logo onto the canvas
  final dstX = (newWidth - original.width) ~/ 2;
  final dstY = (newHeight - original.height) ~/ 2;
  
  img.compositeImage(canvas, original, dstX: dstX, dstY: dstY);

  // Save the result
  File('assets/images/ios_icon.png').writeAsBytesSync(img.encodePng(canvas));
  print('Successfully generated ios_icon.png with navy blue background and 80% safe area scaling.');
}
