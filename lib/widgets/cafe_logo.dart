import 'package:flutter/material.dart';
import '../core/design/tokens.dart';

/// The steaming-cup mark from the mockup, drawn with a [CustomPainter].
/// Steam is a subtle static accent — kept cheap and dependency-free.
class CafeLogo extends StatelessWidget {
  const CafeLogo({super.key, this.size = 26, this.withSteam = true});
  final double size;
  final bool withSteam;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: size,
      height: size * (withSteam ? 1.4 : 1.0),
      child: CustomPaint(
        painter: _CupPainter(
          clay: c.clay,
          honey: c.honey,
          withSteam: withSteam,
        ),
      ),
    );
  }
}

class _CupPainter extends CustomPainter {
  _CupPainter({
    required this.clay,
    required this.honey,
    required this.withSteam,
  });
  final Color clay;
  final Color honey;
  final bool withSteam;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cupTop = withSteam ? size.height - w : 0.0;
    final s = w / 24.0; // scale from the 24px viewBox
    double x(double v) => v * s;
    double y(double v) => cupTop + v * s;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = clay;

    // cup body: M4 9 h12 v5 a6 6 0 0 1-12 0 z
    final body = Path()
      ..moveTo(x(4), y(9))
      ..lineTo(x(16), y(9))
      ..lineTo(x(16), y(14))
      ..arcToPoint(
        Offset(x(4), y(14)),
        radius: Radius.circular(x(6)),
        clockwise: true,
      )
      ..close();
    canvas.drawPath(body, stroke);

    // handle: M16 10 h2.5 a2.5 2.5 0 0 1 0 5 H16
    final handle = Path()
      ..moveTo(x(16), y(10))
      ..lineTo(x(18.5), y(10))
      ..arcToPoint(
        Offset(x(18.5), y(15)),
        radius: Radius.circular(x(2.5)),
        clockwise: true,
      )
      ..lineTo(x(16), y(15));
    canvas.drawPath(handle, stroke);

    // saucer line (honey)
    canvas.drawLine(
      Offset(x(4), y(19.5)),
      Offset(x(16), y(19.5)),
      stroke..color = honey,
    );

    if (withSteam) {
      final steam = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * s
        ..strokeCap = StrokeCap.round
        ..color = honey.withValues(alpha: 0.6);
      for (var i = 0; i < 3; i++) {
        final sx = x(8.0 + i * 2.0);
        canvas.drawLine(
          Offset(sx, cupTop * 0.15),
          Offset(sx, cupTop * 0.75),
          steam,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CupPainter old) =>
      old.clay != clay || old.honey != honey || old.withSteam != withSteam;
}
