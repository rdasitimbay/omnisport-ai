import 'dart:io';
import 'package:image/image.dart' as img;
void main() {
  final imgBytes = File('assets/images/logo_app_os_ai_pure.png').readAsBytesSync();
  final image = img.decodeImage(imgBytes)!;
  final pixel = image.getPixel(0, 0);
  print('Size: ' + image.width.toString() + 'x' + image.height.toString());
  print('Top-Left Pixel: R=' + pixel.r.toString() + ' G=' + pixel.g.toString() + ' B=' + pixel.b.toString() + ' A=' + pixel.a.toString());
}
