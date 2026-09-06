import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft classroom atmosphere: window light + subtle grid like lined paper.
class ClassroomBackdrop extends StatelessWidget {
  const ClassroomBackdrop({
    super.key,
    this.child,
    this.dim = 0.0,
  });

  final Widget? child;
  final double dim;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFD8EEF2),
                Color(0xFFB7DCE4),
                Color(0xFF7FB8C4),
                Color(0xFF1F6F7C),
              ],
              stops: [0.0, 0.35, 0.7, 1.0],
            ),
          ),
        ),
        // Soft sun wash from the upper-left "window".
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.75, -0.85),
              radius: 1.15,
              colors: [
                Color(0x66FFF6D8),
                Color(0x00FFFFFF),
              ],
            ),
          ),
        ),
        CustomPaint(painter: _NotebookGridPainter()),
        if (dim > 0)
          ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ?child,
      ],
    );
  }
}

class _NotebookGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.045)
      ..strokeWidth = 1;

    const step = 28.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PulseRing extends StatelessWidget {
  const PulseRing({
    super.key,
    required this.active,
    required this.child,
    this.diameter = 108,
  });

  final bool active;
  final Widget child;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: active ? 1 : 0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              _BreathingHalo(progress: value, diameter: diameter),
            child,
          ],
        );
      },
    );
  }
}

class _BreathingHalo extends StatefulWidget {
  const _BreathingHalo({
    required this.progress,
    required this.diameter,
  });

  final double progress;
  final double diameter;

  @override
  State<_BreathingHalo> createState() => _BreathingHaloState();
}

class _BreathingHaloState extends State<_BreathingHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final scale = 1.0 + (0.18 * t * widget.progress);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: widget.diameter,
            height: widget.diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.chalk.withValues(
                  alpha: 0.55 * widget.progress * (1 - t * 0.35),
                ),
                width: 2.5,
              ),
            ),
          ),
        );
      },
    );
  }
}

class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class ConnectingDots extends StatefulWidget {
  const ConnectingDots({super.key, this.color = Colors.white});

  final Color color;

  @override
  State<ConnectingDots> createState() => _ConnectingDotsState();
}

class _ConnectingDotsState extends State<ConnectingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_controller.value + i * 0.2) % 1.0;
            final y = math.sin(phase * math.pi * 2) * 4;
            return Transform.translate(
              offset: Offset(0, -y),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.55 + phase * 0.45),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
