import 'package:flutter/material.dart';

import 'theme.dart';

class FuturisticShell extends StatelessWidget {
  const FuturisticShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: gridBlack),
        CustomPaint(painter: _GridPainter(), child: const SizedBox.expand()),
        CustomPaint(painter: _ScanPainter(), child: const SizedBox.expand()),
        child,
        const IgnorePointer(child: CustomPaint(painter: _CornerPainter(), child: SizedBox.expand())),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridCyan.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x1200FFD0);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = gridCyan
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    const arm = 22.0;
    const pad = 10.0;
    void corner(double x, double y, double dx, double dy) {
      canvas.drawLine(Offset(x, y), Offset(x + dx * arm, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + dy * arm), p);
    }

    corner(pad, pad, 1, 1);
    corner(size.width - pad, pad, -1, 1);
    corner(pad, size.height - pad, 1, -1);
    corner(size.width - pad, size.height - pad, -1, -1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HudFrame extends StatelessWidget {
  const HudFrame({
    super.key,
    required this.child,
    this.color = gridCyan,
    this.fill = false,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 12),
  });

  final Widget child;
  final Color color;
  final bool fill;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: HudShapePainter(color: color, fill: fill),
      child: Padding(padding: padding, child: child),
    );
  }
}

class HudShapePainter extends CustomPainter {
  HudShapePainter({required this.color, required this.fill});

  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    const cut = 10.0;
    final path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();

    if (fill) {
      canvas.drawPath(path, Paint()..color = color);
    } else {
      canvas.drawPath(path, Paint()..color = gridPanel);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final tick = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(cut, 0), const Offset(cut + 16, 0), tick);
    canvas.drawLine(Offset(size.width - cut - 16, size.height), Offset(size.width - cut, size.height), tick);
  }

  @override
  bool shouldRepaint(covariant HudShapePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.fill != fill;
  }
}

class HudBar extends StatelessWidget {
  const HudBar({super.key, required this.left, required this.right});

  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF00221A),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(left, style: mono(color: gridCyan, size: 12, weight: FontWeight.bold)),
          const Spacer(),
          Text(right, style: mono(color: gridDim, size: 11)),
        ],
      ),
    );
  }
}
