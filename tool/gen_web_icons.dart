// Web (PWA) icon generator.
//
// Writes every image the browser build serves — `web/favicon.png` and the four
// `web/icons/*.png` entries `web/manifest.json` declares — from the same source
// art the native platforms use. Those files arrive from `flutter create` as
// the stock Flutter logo, and nothing in the toolchain ever replaces them:
// `flutter_launcher_icons` has no web target at all, so without this script the
// browser tab, the install prompt and the iOS "Add to Home Screen" tile all
// keep showing somebody else's logo forever.
//
// Three framings, one source, for reasons the platforms impose:
//
//   * **`purpose: any`** (Icon-192/512) is the art as authored, full bleed. An
//     "any" icon is presented as-is — the browser may round its corners but it
//     never crops — so the source's own generous margin is exactly right. This
//     is also what `<link rel="apple-touch-icon">` points at, and iOS masks a
//     home-screen tile itself, from a full-bleed square, same as here.
//
//   * **`purpose: maskable`** (Icon-maskable-192/512) is derived from
//     `assets/icon/app_icon_foreground.png` — the Android adaptive foreground
//     that `gen_adaptive_foreground.dart` already produces. That is not a
//     coincidence worth re-deriving: the maskable contract (subject inside a
//     centred circle of 80% of the canvas, field bleeding to every edge) is a
//     *looser* version of Android's adaptive one (safe zone ~61%), so an asset
//     built for the strict case satisfies the loose one with room to spare.
//     [_assertMaskableSafeZone] measures that rather than assuming it, because
//     the failure — a saucer clipped by one launcher's mask on one platform —
//     is not something anybody sees until a user reports it.
//
//   * **`favicon.png`** is the one deliberate departure: the art centre-cropped
//     so the cup fills ~78% of the frame instead of ~57%. A favicon is drawn at
//     16 CSS pixels. At that size the source's margin costs almost half the
//     linear resolution of the only thing in the picture, and the tab reads as
//     a brown square. Same reasoning as the small-slot body ratio in
//     `gen_macos_icon.dart`: below a certain size, margin is a luxury the icon
//     cannot pay for. The field colour is untouched, so it still reads as the
//     same icon, just closer in.
//
// The field colour and subject bounding box are detected from the art (the same
// flat-field technique as `gen_adaptive_foreground.dart`), so this stays correct
// if the source is re-exported.
//
// Run order after changing `assets/icon/app_icon.png`:
//
//   dart run tool/gen_adaptive_foreground.dart   # source art -> foreground PNG
//   dart run tool/gen_web_icons.dart             # both        -> web/ icons
//
// It also writes `build/web_icon_preview.png` (gitignored): the maskable icon
// beside a circle-masked copy of itself, for eyeballing what a launcher will
// actually cut. The safe-zone check above is the machine's opinion; the preview
// is there for the human's.
//
// Pure Dart (no Flutter imports); depends only on the `image` dev dependency.

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const String _kSrcPath = 'assets/icon/app_icon.png';
const String _kForegroundPath = 'assets/icon/app_icon_foreground.png';
const String _kIconsDir = 'web/icons';
const String _kFaviconPath = 'web/favicon.png';
const String _kPreviewPath = 'build/web_icon_preview.png';

/// The manifest's two icon sizes, for both purposes.
const List<int> kManifestSizes = [192, 512];

/// Favicon canvas. Browsers ask for 16 CSS pixels and pick the largest source
/// they are offered, so this is 4x the nominal size: enough for a 2x display
/// showing a 32px tab icon, and still under 5 KB.
const int kFaviconSize = 64;

/// Subject width as a fraction of the favicon canvas — see the header for why
/// this one framing is cropped rather than full bleed.
const double kFaviconSubjectFrac = 0.78;

/// How close a pixel must be to the field colour (per channel) to count as
/// background rather than subject. Matches `gen_adaptive_foreground.dart`.
const int kFieldTolerance = 26;

/// The maskable safe zone: a centred circle of 80% of the canvas *diameter*,
/// per the W3C manifest spec's `purpose: maskable` guidance. Everything the
/// icon cannot afford to lose has to sit inside a radius of 0.4 canvases.
const double kMaskableSafeRadiusFrac = 0.4;

/// Tight bounding box of everything that is not the flat field colour.
///
/// Returns `(minX, minY, maxX, maxY)`, inclusive. Throws if the whole image is
/// field — which means the tolerance or the corner sample is wrong, and is
/// worth stopping for rather than writing a blank icon.
(int, int, int, int) _subjectBounds(img.Image src, img.Pixel field) {
  bool isField(img.Pixel p) =>
      (p.r - field.r).abs() < kFieldTolerance &&
      (p.g - field.g).abs() < kFieldTolerance &&
      (p.b - field.b).abs() < kFieldTolerance;

  int minX = src.width, minY = src.height, maxX = 0, maxY = 0;
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      if (isField(src.getPixel(x, y))) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX <= minX || maxY <= minY) {
    stderr.writeln('No subject detected in the art — is the field colour '
        'right? (sampled ${field.r},${field.g},${field.b} at 8,8)');
    exit(1);
  }
  return (minX, minY, maxX, maxY);
}

img.Image _load(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Source art not found at $path');
    exit(1);
  }
  final decoded = img.decodePng(file.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $path as PNG');
    exit(1);
  }
  return decoded;
}

img.Image _resize(img.Image src, int side) => img.copyResize(
      src,
      width: side,
      height: side,
      interpolation: img.Interpolation.cubic,
    );

/// Fails the build if any of the maskable art's subject falls outside the
/// safe-zone circle.
///
/// Measured, not assumed. The whole argument for deriving the maskable icons
/// from the Android foreground is that Android's safe zone is stricter; if the
/// foreground is ever regenerated with a larger subject, or hand-edited, that
/// argument quietly stops holding and a launcher starts clipping the saucer.
///
/// The measurement walks PIXELS rather than the subject's bounding box, and the
/// difference is not pedantry: the subject is a cup on a saucer, roughly
/// elliptical, so the box's corners are field the mask is welcome to eat. Using
/// the box would report ~39% against a 40% limit — a hair's breadth — for art
/// that in fact clears the circle comfortably, and a future edit would then be
/// judged against a number that was never true.
void _assertMaskableSafeZone(img.Image art) {
  final field = art.getPixel(8, 8);
  bool isField(img.Pixel p) =>
      (p.r - field.r).abs() < kFieldTolerance &&
      (p.g - field.g).abs() < kFieldTolerance &&
      (p.b - field.b).abs() < kFieldTolerance;

  final centre = art.width / 2.0;
  var worst = 0.0;
  for (var y = 0; y < art.height; y++) {
    for (var x = 0; x < art.width; x++) {
      if (isField(art.getPixel(x, y))) continue;
      final dx = x + 0.5 - centre;
      final dy = y + 0.5 - centre;
      final r = math.sqrt(dx * dx + dy * dy);
      if (r > worst) worst = r;
    }
  }
  final reach = worst / art.width;

  stdout.writeln('Maskable safe zone: subject reaches '
      '${(reach * 100).toStringAsFixed(1)}% of the canvas '
      '(limit ${(kMaskableSafeRadiusFrac * 100).round()}%).');

  if (reach > kMaskableSafeRadiusFrac) {
    stderr.writeln('The maskable subject escapes the safe-zone circle: a '
        'circular launcher mask would clip it. Re-run '
        'tool/gen_adaptive_foreground.dart with a smaller kTargetFrac, or seat '
        'the subject smaller in $_kForegroundPath.');
    exit(1);
  }
}

/// The art, centre-cropped so its subject spans [subjectFrac] of the result.
///
/// The crop window is clamped to the image, which can only ever make the
/// subject *larger* in frame than asked for — never clip it — because the
/// window is centred on the subject, not on the canvas.
img.Image _cropToSubject(img.Image src, double subjectFrac) {
  final (minX, minY, maxX, maxY) = _subjectBounds(src, src.getPixel(8, 8));
  final subject = math.max(maxX - minX, maxY - minY).toDouble();
  final cx = (minX + maxX) / 2.0;
  final cy = (minY + maxY) / 2.0;

  var side = (subject / subjectFrac).round();
  side = math.min(side, math.min(src.width, src.height));

  var x = (cx - side / 2).round().clamp(0, src.width - side);
  var y = (cy - side / 2).round().clamp(0, src.height - side);

  return img.copyCrop(src, x: x, y: y, width: side, height: side);
}

/// A side-by-side of the maskable icon as authored and as a circular launcher
/// mask will cut it, on a neutral plate so the mask's edge is visible.
void _writePreview(img.Image maskable) {
  const cell = 256;
  const gap = 24;
  final plain = _resize(maskable, cell);
  final masked = _resize(maskable, cell);

  final radius = cell * 0.5;
  final centre = cell / 2.0;
  for (var y = 0; y < cell; y++) {
    for (var x = 0; x < cell; x++) {
      final dx = x + 0.5 - centre;
      final dy = y + 0.5 - centre;
      if (dx * dx + dy * dy > radius * radius) {
        masked.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  final out = img.Image(
    width: cell * 2 + gap * 3,
    height: cell + gap * 2,
    numChannels: 4,
  );
  img.fill(out, color: img.ColorRgba8(0xEE, 0xEE, 0xEE, 0xFF));
  img.compositeImage(out, plain, dstX: gap, dstY: gap);
  img.compositeImage(out, masked, dstX: gap * 2 + cell, dstY: gap);

  Directory(File(_kPreviewPath).parent.path).createSync(recursive: true);
  File(_kPreviewPath).writeAsBytesSync(img.encodePng(out));
  stdout.writeln('Wrote $_kPreviewPath (left: as authored, right: under a '
      'circular mask).');
}

void main() {
  final src = _load(_kSrcPath);
  final foreground = _load(_kForegroundPath);

  _assertMaskableSafeZone(foreground);

  final dir = Directory(_kIconsDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  for (final size in kManifestSizes) {
    final any = File('$_kIconsDir/Icon-$size.png');
    any.writeAsBytesSync(img.encodePng(_resize(src, size)));
    stdout.writeln('Wrote ${any.path} (${size}x$size, purpose any).');

    final maskable = File('$_kIconsDir/Icon-maskable-$size.png');
    maskable.writeAsBytesSync(img.encodePng(_resize(foreground, size)));
    stdout.writeln('Wrote ${maskable.path} (${size}x$size, purpose maskable).');
  }

  final favicon = _resize(_cropToSubject(src, kFaviconSubjectFrac), kFaviconSize);
  File(_kFaviconPath).writeAsBytesSync(img.encodePng(favicon));
  stdout.writeln('Wrote $_kFaviconPath ($kFaviconSize x $kFaviconSize, subject '
      '~${(kFaviconSubjectFrac * 100).round()}% of frame).');

  _writePreview(foreground);
}
