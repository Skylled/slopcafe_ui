// macOS app-icon generator.
//
// Writes every slot of macos/Runner/Assets.xcassets/AppIcon.appiconset from the
// source art at assets/icon/app_icon.png. Unlike Android (where the launcher
// masks the icon for us — see gen_adaptive_foreground.dart) macOS applies *no*
// mask: whatever shape the PNG is, that is the shape in the Dock. A full-bleed
// square source therefore lands as a hard-cornered square wedged between
// rounded neighbours, which is what this script exists to fix.
//
// It seats the art in Apple's macOS icon grid:
//
//   * a rounded-square body centred on the canvas, sized per slot (see
//     [_bodyFor] — the grid is *not* one ratio at every size),
//   * corners are Apple's *continuous* (G2) squircle, not a circular arc — the
//     curvature eases into the straight edge instead of starting abruptly,
//   * a soft drop shadow beneath, so the icon sits on the Dock shelf like the
//     system's own.
//
// Every constant below was measured off Apple's own artwork (the system icons
// in /System/Applications) rather than guessed; see the notes on each.
//
// This owns the macOS appiconset outright — `flutter_launcher_icons` is
// configured with `macos: generate: false`, because it can only downscale a
// single master and that gets the small slots wrong (see [_bodyFor]). After
// changing the source art:
//
//   dart run tool/gen_macos_icon.dart   # source art -> the whole appiconset
//
// Pure Dart (no Flutter imports); depends only on the `image` dev dependency.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const String _kSrcPath = 'assets/icon/app_icon.png';
const String _kOutDir = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

/// The slots referenced by the appiconset's Contents.json.
const List<int> kSizes = [16, 32, 64, 128, 256, 512, 1024];

/// Margin around the icon body for a given canvas, in whole pixels.
///
/// The grid is *not* a single ratio. The 128pt slots and up put an 824px body
/// on a 1024px canvas (a 100px margin, ~80.5%), but the 16pt and 32pt slots —
/// canvases of 16, 32 and 64px — use 7/8 of the canvas instead, because a
/// proportional margin would burn pixels an icon that small cannot spare.
///
/// The margin is then a whole number of pixels, so the body's straight edges
/// land on the pixel grid instead of straddling it. That rounding is visible
/// at 128px, where the ratio wants 12.5 and Apple ships 12 — a 104px body, not
/// 103. Verified against the system icons, which measure bodies of 14/16,
/// 28/32, 104/128 and 206/256. None of this survives downscaling one master,
/// which is why flutter_launcher_icons cannot generate these.
int _marginFor(int canvas) =>
    canvas <= 64 ? canvas ~/ 16 : (canvas * 100 / 1024).floor();

double _bodyFor(int canvas) => (canvas - 2 * _marginFor(canvas)).toDouble();

/// Corner radius, as a fraction of the *body* side (185.4 of 824 in Apple's
/// macOS icon template).
const double kRadiusFrac = 185.4 / 824.0;

/// Corner smoothing: how far the curvature eases out into the straight edge.
/// 0 is a plain circular rounded rect; 1 is a corner with no circular section
/// left at all, and the corner reaches `(1 + smoothing) * radius` along each
/// edge. Fitted by rasterising candidates and diffing the binary silhouette
/// against Podcasts / Reminders / App Store / Music / Notes (which all share
/// one exact silhouette): the error floor is a plateau over 0.53..0.61 at
/// 0.26px RMS on a 206px body, so anything in there is Apple's shape to well
/// under a pixel. The same sweep independently recovered [kRadiusFrac].
const double kSmoothing = 0.6;

/// Coverage samples per pixel per axis when rasterising the body. 4 (16
/// samples/px) is past the point where more is visible at any Dock size.
const int kSuperSample = 4;

/// Drop shadow, as fractions of the canvas. Fitted to the alpha falloff around
/// the system icons, which at 256px is ~30% black, Gaussian sigma 3, pushed
/// 2.8px down — i.e. sigma 12 and offset 11 on a 1024px canvas.
const double kShadowOpacity = 0.30;
const double kShadowSigmaFrac = 12.0 / 1024.0;
const double kShadowOffsetFrac = 11.0 / 1024.0;

/// Sample count along each of the corner's three segments.
const int _kCurveSamples = 2000;

/// Resolution of the corner lookup table.
const int _kTableSize = 4096;

/// One corner of the squircle, as a lookup table.
///
/// Apple's corner is not a circular arc. It is three pieces: a cubic Bézier
/// easing off the straight edge, a circular arc through the middle of the
/// turn, and the mirrored Bézier easing back onto the next edge. Smoothing
/// trades arc for Bézier — at `smoothing == 0` the Béziers collapse to nothing
/// and this degenerates to an ordinary rounded rectangle.
class CornerProfile {
  CornerProfile._(this.span, this._table);

  /// How far the corner reaches along each edge, `(1 + smoothing) * radius`.
  /// Beyond this the edge is straight.
  final double span;

  /// Boundary depth (distance below the top edge) sampled uniformly over
  /// `x in [0, span]`, measured from where the straight edge ends.
  final Float64List _table;

  factory CornerProfile(double radius, double smoothing) {
    final s = smoothing.clamp(0.0, 1.0);
    final r = radius;
    final span = (1 + s) * r;

    // Angles, in radians. The arc keeps whatever the Béziers do not take.
    final arcSweep = (math.pi / 2) * (1 - s);
    final alpha = (math.pi / 4) * s; // tilt of the Bézier/arc junction
    final beta = (math.pi / 4) * s;

    // Bézier control offsets, laid out along the edge then lifted by `d`.
    final arcChord = math.sin(arcSweep / 2) * r * math.sqrt2;
    final c = r * math.tan(beta / 2) * math.cos(alpha);
    final d = c * math.tan(alpha);
    final b = (span - arcChord - c - d) / 3;
    final a = 2 * b;

    final xs = <double>[];
    final ys = <double>[];
    void add(double x, double y) {
      xs.add(x);
      ys.add(y);
    }

    // Segment 1 — cubic Bézier easing off the straight edge. Control points
    // sit *on* the edge (y == 0), which is what makes the curvature start at
    // zero and the join invisible.
    final p3x = a + b + c, p3y = d;
    for (var i = 0; i <= _kCurveSamples; i++) {
      final t = i / _kCurveSamples;
      final mt = 1 - t;
      final x = 3 * mt * mt * t * a + 3 * mt * t * t * (a + b) + t * t * t * p3x;
      final y = t * t * t * p3y;
      add(x, y);
    }

    // Segment 2 — circular arc. Its centre is one radius along the inward
    // normal at the Bézier's end, where the tangent is already tilted by
    // `alpha`, so the two meet with matching curvature.
    final ccx = p3x - r * math.sin(alpha);
    final ccy = p3y + r * math.cos(alpha);
    final phi0 = -math.pi / 2 + alpha;
    for (var i = 0; i <= _kCurveSamples; i++) {
      final phi = phi0 + arcSweep * (i / _kCurveSamples);
      add(ccx + r * math.cos(phi), ccy + r * math.sin(phi));
    }

    // Segment 3 — the mirror of segment 1, easing onto the next edge.
    final p4x = ccx + r * math.cos(phi0 + arcSweep);
    final p4y = ccy + r * math.sin(phi0 + arcSweep);
    for (var i = 0; i <= _kCurveSamples; i++) {
      final t = i / _kCurveSamples;
      final mt = 1 - t;
      final x = p4x + d * (1 - mt * mt * mt);
      final y = p4y +
          3 * mt * mt * t * c +
          3 * mt * t * t * (b + c) +
          t * t * t * (a + b + c);
      add(x, y);
    }

    // Resample onto a uniform x grid. The curve is monotone in x across all
    // three segments, so a single forward walk suffices.
    final table = Float64List(_kTableSize + 1);
    var j = 0;
    for (var i = 0; i <= _kTableSize; i++) {
      final x = span * i / _kTableSize;
      while (j < xs.length - 2 && xs[j + 1] < x) {
        j++;
      }
      final x0 = xs[j], x1 = xs[j + 1];
      final f = (x1 - x0).abs() < 1e-12 ? 0.0 : (x - x0) / (x1 - x0);
      table[i] = (ys[j] + (ys[j + 1] - ys[j]) * f).clamp(0.0, span);
    }
    table[_kTableSize] = span;
    return CornerProfile._(span, table);
  }

  /// Boundary depth at `x` measured from where the straight edge ends.
  double depthAt(double x) {
    if (x <= 0) return 0;
    if (x >= span) return span;
    final u = x / span * _kTableSize;
    final i = u.floor();
    if (i >= _kTableSize) return span;
    return _table[i] + (_table[i + 1] - _table[i]) * (u - i);
  }
}

/// Antialiased coverage of a squircle body of side [body], centred on a
/// [canvas]x[canvas] grid, as 0..1 alpha. [body] may be fractional — the 128px
/// slot's is 103.0 on a 128px canvas, so the margin lands on a half pixel.
Float64List renderBodyMask(
  int canvas,
  double body, {
  double radiusFrac = kRadiusFrac,
  double smoothing = kSmoothing,
  int superSample = kSuperSample,
}) {
  final centre = canvas / 2.0;
  final half = body / 2.0;
  final profile = CornerProfile(body * radiusFrac, smoothing);
  final span = profile.span;
  final mask = Float64List(canvas * canvas);
  final step = 1.0 / superSample;
  final weight = 1.0 / (superSample * superSample);

  for (var py = 0; py < canvas; py++) {
    for (var px = 0; px < canvas; px++) {
      var cov = 0.0;
      for (var sy = 0; sy < superSample; sy++) {
        final y = py + (sy + 0.5) * step;
        // Distance inside the nearest horizontal edge.
        final b = half - (y - centre).abs();
        if (b <= 0) continue;
        for (var sx = 0; sx < superSample; sx++) {
          final x = px + (sx + 0.5) * step;
          // Distance inside the nearest vertical edge.
          final a = half - (x - centre).abs();
          if (a <= 0) continue;
          if (a >= span || b >= span || b >= profile.depthAt(span - a)) {
            cov += weight;
          }
        }
      }
      mask[py * canvas + px] = cov;
    }
  }
  return mask;
}

/// Separable Gaussian blur over a [size]x[size] scalar field.
Float64List _blur(Float64List src, int size, double sigma) {
  if (sigma < 0.05) return src;
  final radius = (sigma * 3).ceil();
  final kernel = Float64List(radius * 2 + 1);
  var sum = 0.0;
  for (var i = -radius; i <= radius; i++) {
    final v = math.exp(-(i * i) / (2 * sigma * sigma));
    kernel[i + radius] = v;
    sum += v;
  }
  for (var i = 0; i < kernel.length; i++) {
    kernel[i] /= sum;
  }

  final tmp = Float64List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var acc = 0.0;
      for (var k = -radius; k <= radius; k++) {
        final sx = x + k;
        if (sx < 0 || sx >= size) continue;
        acc += src[y * size + sx] * kernel[k + radius];
      }
      tmp[y * size + x] = acc;
    }
  }
  final out = Float64List(size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      var acc = 0.0;
      for (var k = -radius; k <= radius; k++) {
        final sy = y + k;
        if (sy < 0 || sy >= size) continue;
        acc += tmp[sy * size + x] * kernel[k + radius];
      }
      out[y * size + x] = acc;
    }
  }
  return out;
}

/// One appiconset slot, rendered at its native resolution. Rendering rather
/// than downscaling a master keeps the small slots crisp: at 16px the squircle
/// is only ~3px of curve, and resampling it out of a 1024px alpha channel
/// smears the rim that native supersampling resolves cleanly.
img.Image renderIcon(img.Image src, int canvas) {
  final body = _bodyFor(canvas);
  final mask = renderBodyMask(canvas, body);

  // Shadow: the body silhouette, pushed down, blurred, and dimmed.
  final sigma = canvas * kShadowSigmaFrac;
  final offset = canvas * kShadowOffsetFrac;
  final field = Float64List(canvas * canvas);
  final shift = offset.round();
  for (var y = 0; y < canvas; y++) {
    final sy = y - shift;
    if (sy < 0 || sy >= canvas) continue;
    for (var x = 0; x < canvas; x++) {
      field[y * canvas + x] = mask[sy * canvas + x];
    }
  }
  final shadow = _blur(field, canvas, sigma);

  // The art, scaled a touch proud of the body so it always covers the mask's
  // antialiased rim even when the margin lands on a half pixel.
  final artSide = body.ceil() + 2;
  final art = img.copyResize(
    src,
    width: artSide,
    height: artSide,
    interpolation: img.Interpolation.cubic,
  );
  final artOrigin = ((canvas - artSide) / 2).round();

  final out = img.Image(width: canvas, height: canvas, numChannels: 4);
  for (var y = 0; y < canvas; y++) {
    for (var x = 0; x < canvas; x++) {
      final cov = mask[y * canvas + x];
      final sa = shadow[y * canvas + x] * kShadowOpacity;

      // Shadow first (black), then the masked art over it, source-over — so
      // the shadow still shows through the body's antialiased rim.
      final outA = cov + sa * (1 - cov);
      if (outA <= 0) continue;

      final ax = x - artOrigin, ay = y - artOrigin;
      num sr = 0, sg = 0, sb = 0;
      if (cov > 0 && ax >= 0 && ay >= 0 && ax < artSide && ay < artSide) {
        final p = art.getPixel(ax, ay);
        sr = p.r;
        sg = p.g;
        sb = p.b;
      }
      double blend(num c) => (c * cov) / outA; // shadow contributes black
      out.setPixelRgba(
        x,
        y,
        blend(sr).round().clamp(0, 255),
        blend(sg).round().clamp(0, 255),
        blend(sb).round().clamp(0, 255),
        (outA * 255).round().clamp(0, 255),
      );
    }
  }
  return out;
}

void main() {
  final srcFile = File(_kSrcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('Source art not found at $_kSrcPath');
    exit(1);
  }
  final src = img.decodePng(srcFile.readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $_kSrcPath as PNG');
    exit(1);
  }
  final outDir = Directory(_kOutDir);
  if (!outDir.existsSync()) {
    stderr.writeln('Appiconset not found at $_kOutDir');
    exit(1);
  }

  for (final size in kSizes) {
    final icon = renderIcon(src, size);
    final path = '$_kOutDir/app_icon_$size.png';
    File(path).writeAsBytesSync(img.encodePng(icon));
    stdout.writeln('Wrote $path '
        '(${size}x$size, body ${_bodyFor(size).toStringAsFixed(1)}px, '
        'radius ${(_bodyFor(size) * kRadiusFrac).toStringAsFixed(1)}px)');
  }
  stdout.writeln('Done — ${kSizes.length} slots, smoothing $kSmoothing.');
}
