import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Lato massimo e qualità delle foto salvate: restano ben sotto il limite di
/// 1 MB dei documenti Firestore anche dopo la codifica base64.
const int photoMaxSide = 1280;
const int photoQuality = 72;

/// Ridimensiona e ricomprime una foto in JPEG (in un isolate separato).
Future<Uint8List> compressPhoto(Uint8List bytes) => compute(_compress, bytes);

Uint8List _compress(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('image');
  var im = img.bakeOrientation(decoded);
  final side = im.width > im.height ? im.width : im.height;
  if (side > photoMaxSide) {
    im = im.width >= im.height
        ? img.copyResize(im, width: photoMaxSide, interpolation: img.Interpolation.average)
        : img.copyResize(im, height: photoMaxSide, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(im, quality: photoQuality);
}
