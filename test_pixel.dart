import 'dart:io';
import 'package:image/image.dart' as img;
void main() {
  final imgBytes = File('assets/images/app_logo_shield_premium_fin.png').readAsBytesSync();
  final image = img.decodeImage(imgBytes)!;
  final pixel = image.getPixel(0, 0);
  print('Top-Left Pixel: R=' + pixel.r.toString() + ' G=' + pixel.g.toString() + ' B=' + pixel.b.toString() + ' A=' + pixel.a.toString());
}
