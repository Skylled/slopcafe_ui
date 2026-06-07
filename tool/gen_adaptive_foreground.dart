// Android adaptive-icon foreground generator.
//
// Derives assets/icon/app_icon_foreground.png from the source art at
// assets/icon/app_icon.png. The source is a full-bleed design (a coffee cup on
// a flat brown field). An Android adaptive icon masks the foreground to the
// launcher's shape and only guarantees the central "safe zone" (~66 of 108 dp,
// ~61%) is visible. This script lifts the cup+saucer out of the source and
// re-seats it, pre-scaled, into that safe zone on a matching brown field, so:
//
//   * the brown bleeds edge-to-edge under any mask (background layer is the same
//     colour, declared in pubspec as adaptive_icon_background), and
//   * the saucer is never clipped, because the mask only ever cuts brown.
//
// The field colour and subject bounding box are detected from the art, so this
// stays correct if the source is re-exported. After running this, regenerate
// the platform icons:
//
//   dart run tool/gen_adaptive_foreground.dart   # source art -> foreground PNG
//   dart run flutter_launcher_icons              # foreground  -> mipmap/anydpi
//
// Pure Dart (no Flutter imports); depends only on the `image` dev dependency.

import 'dart:io';

import 'package:image/image.dart' as img;

/// Foreground canvas size. flutter_launcher_icons downscales this per density.
const int kCanvas = 1080;

/// Subject width as a fraction of the canvas. Kept under the ~0.61 safe-zone
/// fraction so the saucer sits inside the mask with a little breathing room.
const double kTargetFrac = 0.56;

/// How close a pixel must be to the field colour (per channel) to count as
/// background rather than subject, when detecting the subject's bounding box.
const int kFieldTolerance = 26;

void main() {
  const srcPath = 'assets/icon/app_icon.png';
  const outPath = 'assets/icon/app_icon_foreground.png';

  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('Source art not found at $srcPath');
    exit(1);
  }
  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $srcPath as PNG');
    exit(1);
  }

  // The flat field colour, sampled from a corner the subject never reaches.
  final field = src.getPixel(8, 8);

  bool isField(img.Pixel p) =>
      (p.r - field.r).abs() < kFieldTolerance &&
      (p.g - field.g).abs() < kFieldTolerance &&
      (p.b - field.b).abs() < kFieldTolerance;

  // Tight bounding box of the non-field subject (cup + saucer + shadow).
  int minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (!isField(src.getPixel(x, y))) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX <= minX || maxY <= minY) {
    stderr.writeln('No subject detected — is the field colour right?');
    exit(1);
  }
  final subjW = maxX - minX;
  final subjCx = (minX + maxX) / 2.0;
  final subjCy = (minY + maxY) / 2.0;

  // Scale the whole source so the subject spans kTargetFrac of the canvas, then
  // composite it (it carries its own matching brown field) onto a brown canvas,
  // recentred so the subject's bbox centre lands at the canvas centre.
  final scale = (kTargetFrac * kCanvas) / subjW;
  final scaledW = (src.width * scale).round();
  final scaledH = (src.height * scale).round();
  final scaled = img.copyResize(
    src,
    width: scaledW,
    height: scaledH,
    interpolation: img.Interpolation.cubic,
  );

  final dstX = (kCanvas / 2 - subjCx * scale).round();
  final dstY = (kCanvas / 2 - subjCy * scale).round();

  final out = img.Image(width: kCanvas, height: kCanvas, numChannels: 4);
  img.fill(out, color: field);
  img.compositeImage(out, scaled, dstX: dstX, dstY: dstY);

  File(outPath).writeAsBytesSync(img.encodePng(out));

  final hex = '#${field.r.toInt().toRadixString(16).padLeft(2, '0')}'
          '${field.g.toInt().toRadixString(16).padLeft(2, '0')}'
          '${field.b.toInt().toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
  stdout.writeln('Wrote $outPath '
      '(${kCanvas}x$kCanvas, field $hex, subject ~${(kTargetFrac * 100).round()}% '
      'of canvas, scale ${scale.toStringAsFixed(3)}).');
  stdout.writeln('Set adaptive_icon_background to $hex in pubspec.yaml, '
      'then run: dart run flutter_launcher_icons');
}
