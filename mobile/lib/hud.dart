import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

class FuturisticShell extends StatefulWidget {
  const FuturisticShell({super.key, required this.child});

  final Widget child;

  @override
  State<FuturisticShell> createState() => _FuturisticShellState();
}

class _FuturisticShellState extends State<FuturisticShell> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800))..repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: gridBlack),
        CustomPaint(painter: _GridPainter(), child: const SizedBox.expand()),
        CustomPaint(painter: _ScanPainter(), child: const SizedBox.expand()),
        AnimatedBuilder(
          animation: _sweep,
          builder: (context, _) {
            return CustomPaint(painter: _SweepPainter(_sweep.value), child: const SizedBox.expand());
          },
        ),
        widget.child,
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

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final y = (t * (size.height + 90)) - 50;
    final rect = Rect.fromLTWH(0, y, size.width, 36);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x0000FFD0), Color(0x2800FFD0), Color(0x0000FFD0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) => oldDelegate.t != t;
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
  const HudBar({super.key, required this.left, required this.right, this.live = false});

  final String left;
  final String right;
  final bool live;

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
          if (live) ...[const PulseLive(), const SizedBox(width: 8)],
          Text(right, style: mono(color: gridDim, size: 11)),
        ],
      ),
    );
  }
}

class PulseLive extends StatefulWidget {
  const PulseLive({super.key});

  @override
  State<PulseLive> createState() => _PulseLiveState();
}

class _PulseLiveState extends State<PulseLive> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.25, end: 1).animate(_ctrl),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: gridCyan,
          boxShadow: [BoxShadow(color: gridCyan.withValues(alpha: 0.8), blurRadius: 8)],
        ),
      ),
    );
  }
}

class HudButton extends StatefulWidget {
  const HudButton({super.key, required this.label, required this.onPressed, this.filled = true});

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  State<HudButton> createState() => _HudButtonState();
}

class _HudButtonState extends State<HudButton> {
  bool _down = false;

  void _press() {
    HapticFeedback.mediumImpact();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.filled ? (_down ? gridSoft : gridCyan) : Colors.transparent;
    final fg = widget.filled ? gridBlack : gridCyan;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: _press,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 80),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: gridCyan, width: 1.4),
            boxShadow: _down || widget.filled
                ? [BoxShadow(color: gridCyan.withValues(alpha: 0.35), blurRadius: _down ? 4 : 14, spreadRadius: 1)]
                : null,
          ),
          child: Text(widget.label, textAlign: TextAlign.center, style: mono(color: fg, size: 16, weight: FontWeight.bold)),
        ),
      ),
    );
  }
}

class LatticeRoute<T> extends PageRouteBuilder<T> {
  LatticeRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondary) => builder(context),
          transitionDuration: const Duration(milliseconds: 420),
          reverseTransitionDuration: const Duration(milliseconds: 260),
          transitionsBuilder: (context, animation, secondary, child) {
            final fade = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.035), end: Offset.zero).animate(fade),
                child: child,
              ),
            );
          },
        );
}
