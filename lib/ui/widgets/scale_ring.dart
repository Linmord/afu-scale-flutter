import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart' as th;

/// 测量阶段：称重 / 阻抗 / 完成
enum RingPhase { idle, weighing, impedance, done }

class ScaleRing extends StatefulWidget {
  final double weightKg;
  final String unitSuffix;
  final String unitNum;
  final RingPhase phase;
  final bool electrodeOn;
  final String statusText;
  final bool timedOut;
  /// 未开始测量时圆环中央显示的提示（为空则显示 --.--）
  final String idleHint;
  const ScaleRing({
    super.key,
    required this.weightKg,
    required this.unitNum,
    required this.unitSuffix,
    required this.phase,
    required this.electrodeOn,
    required this.statusText,
    this.timedOut = false,
    this.idleHint = '',
  });
  @override State<ScaleRing> createState() => _ScaleRingState();
}

class _ScaleRingState extends State<ScaleRing> with TickerProviderStateMixin {
  late final AnimationController _progress;   // 环形进度
  late final AnimationController _wave;       // 液体波动
  late final AnimationController _pulse;      // 脉冲波纹（阻抗阶段）
  late final AnimationController _bounce;     // 完成回弹

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant ScaleRing old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) _syncAnimations();
  }

  void _syncAnimations() {
    switch (widget.phase) {
      case RingPhase.idle:
        _progress.animateTo(0, duration: const Duration(milliseconds: 300));
        break;
      case RingPhase.weighing:
        _progress.animateTo(0.42, curve: Curves.easeOutCubic);
        break;
      case RingPhase.impedance:
        _progress.animateTo(0.74, curve: Curves.easeOutCubic);
        break;
      case RingPhase.done:
        _progress.animateTo(1.0, curve: Curves.easeOutCubic);
        _bounce.forward(from: 0);
        break;
    }
  }

  @override
  void dispose() {
    _progress.dispose(); _wave.dispose(); _pulse.dispose(); _bounce.dispose();
    super.dispose();
  }

  Color get _ringColor {
    switch (widget.phase) {
      case RingPhase.done: return th.AppColors.primary;
      case RingPhase.impedance:
        return widget.electrodeOn ? th.AppColors.accent : th.AppColors.warn;
      case RingPhase.weighing: return th.AppColors.accent;
      default: return th.AppColors.borderStrong;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: Listenable.merge([_progress, _wave, _pulse, _bounce]),
        builder: (ctx, _) {
          final p = _progress.value;
          final showPulse = widget.phase == RingPhase.impedance && widget.electrodeOn;
          return CustomPaint(
            painter: _RingPainter(
              progress: p,
              wavePhase: _wave.value,
              pulsePhase: _pulse.value,
              showPulse: showPulse,
              phase: widget.phase,
              electrodeOn: widget.electrodeOn,
              ringColor: _ringColor,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _weightText(),
                  const SizedBox(height: 4),
                  Text(
                    widget.statusText,
                    style: TextStyle(
                      color: widget.timedOut ? th.AppColors.warn : th.AppColors.textSub,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _weightText() {
    final scale = widget.phase == RingPhase.done
        ? 1.0 + (1 - Curves.elasticOut.transform(_bounce.value)) * 0.12
        : 1.0;
    final hasValue = widget.weightKg > 0;
    return Transform.scale(
      scale: scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                hasValue
                    ? widget.unitNum
                    : (widget.idleHint.isNotEmpty ? widget.idleHint : '--.--'),
                style: TextStyle(
                  fontSize: hasValue || widget.idleHint.isEmpty ? 54 : 22,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: hasValue ? th.AppColors.text : th.AppColors.primary,
                  letterSpacing: -1.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              if (hasValue || widget.idleHint.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  widget.unitSuffix,
                  style: TextStyle(fontSize: 16, color: th.AppColors.textHint, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double wavePhase;
  final double pulsePhase;
  final bool showPulse;
  final RingPhase phase;
  final bool electrodeOn;
  final Color ringColor;
  _RingPainter({
    required this.progress,
    required this.wavePhase,
    required this.pulsePhase,
    required this.showPulse,
    required this.phase,
    required this.electrodeOn,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    const strokeW = 14.0;

    // 底盘
    canvas.drawCircle(
      center, radius,
      Paint()..style = PaintingStyle.fill..color = th.AppColors.surface,
    );
    canvas.drawCircle(
      center, radius,
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = th.AppColors.border,
    );

    // 轨道
    canvas.drawCircle(
      center, radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..color = th.AppColors.surfaceAlt,
    );

    // 液体波动（环形内底部）
    if (phase == RingPhase.weighing || phase == RingPhase.impedance) {
      _paintWave(canvas, center, radius);
    }

    // 脉冲波纹（阻抗阶段）
    if (showPulse) _paintPulse(canvas, center, radius);

    // 进度弧
    if (progress > 0.001) {
      final start = -math.pi / 2;
      final sweep = 2 * math.pi * progress;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect, start, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: start,
            endAngle: start + 2 * math.pi,
            colors: [ringColor.withOpacity(0.35), ringColor],
            transform: GradientRotation(start),
          ).createShader(rect),
      );
      // 弧头光点
      final tipX = center.dx + radius * math.cos(start + sweep);
      final tipY = center.dy + radius * math.sin(start + sweep);
      canvas.drawCircle(
        Offset(tipX, tipY), strokeW / 2 + 3,
        Paint()..color = ringColor.withOpacity(0.22),
      );
      canvas.drawCircle(
        Offset(tipX, tipY), strokeW / 2,
        Paint()..color = ringColor,
      );
    }
  }

  void _paintWave(Canvas canvas, Offset center, double radius) {
    final waveH = radius * 0.5;
    final clip = Path()..addOval(Rect.fromCircle(center: center, radius: radius - 8));
    canvas.save();
    canvas.clipPath(clip);
    final p = Path();
    final baseY = center.dy + radius * 0.1;
    const amp = 5.0;
    const freq = 2.2;
    p.moveTo(center.dx - radius, baseY);
    for (var x = -radius; x <= radius; x += 4) {
      final y = baseY + math.sin((x / radius) * freq * math.pi + wavePhase * 2 * math.pi) * amp;
      p.lineTo(center.dx + x, y);
    }
    p.lineTo(center.dx + radius, center.dy + radius);
    p.lineTo(center.dx - radius, center.dy + radius);
    p.close();
    canvas.drawPath(
      p,
      Paint()..color = ringColor.withOpacity(0.10),
    );
    canvas.restore();
  }

  void _paintPulse(Canvas canvas, Offset center, double radius) {
    for (var i = 0; i < 3; i++) {
      final t = (pulsePhase + i / 3) % 1.0;
      final r = radius * (0.55 + t * 0.6);
      final alpha = (1 - t) * 0.30;
      canvas.drawCircle(
        center, r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ringColor.withOpacity(alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => true;
}