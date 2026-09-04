import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Flat elevated card — the surface every screen is built from.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? fill;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.radius = 18,
    this.onTap,
    this.borderColor,
    this.fill,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? p.border, width: 1),
      ),
      child: child,
    );

    final tappable = onTap == null
        ? content
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: content,
            ),
          );

    return margin == null
        ? tappable
        : Padding(padding: margin!, child: tappable);
  }
}

/// Small uppercase heading above a list section.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: p.textTertiary,
          letterSpacing: 1.6,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        );
    if (trailing == null) return Text(text.toUpperCase(), style: style);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(text.toUpperCase(), style: style), trailing!],
    );
  }
}

/// Compact status chip — LIVE / DEMO, Complete / Pending, and so on.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: filled ? 0.9 : 0.13),
        borderRadius: BorderRadius.circular(20),
        border: filled
            ? null
            : Border.all(color: color.withValues(alpha: 0.32), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: filled ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: filled ? Colors.white : color,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
          ),
        ],
      ),
    );
  }
}

/// Thin rounded progress bar used under course cards and category rows.
class ThinProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  final bool animate;

  const ThinProgressBar({
    super.key,
    required this.value,
    required this.color,
    this.height = 5,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    Widget bar(double v) => ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: LinearProgressIndicator(
            value: v,
            minHeight: height,
            backgroundColor: p.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        );
    if (!animate) return bar(clamped);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: clamped),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => bar(v),
    );
  }
}

/// A label above a value — the building block of the overview stat grid.
class MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final CrossAxisAlignment align;

  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.align = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: tt.labelSmall?.copyWith(
            color: p.textTertiary,
            fontSize: 9.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tt.titleMedium?.copyWith(
            color: valueColor ?? p.textPrimary,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

/// Circular initials badge, used in the top-right of every screen.
class InitialsAvatar extends StatelessWidget {
  final String name;
  final ImageProvider? image;
  final double radius;

  const InitialsAvatar({
    super.key,
    required this.name,
    this.image,
    this.radius = 17,
  });

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return _firstLetter(parts.first);
    return _firstLetter(parts.first) + _firstLetter(parts.last);
  }

  /// First character by rune, so a name starting with a multi-byte glyph is
  /// not sliced in half.
  static String _firstLetter(String word) {
    final runes = word.runes;
    if (runes.isEmpty) return '';
    return String.fromCharCode(runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (image != null) {
      return CircleAvatar(radius: radius, backgroundImage: image);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: p.surfaceAlt,
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: p.textSecondary,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shimmering placeholder shown while the first sync is in flight.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const Skeleton({super.key, this.height = 16, this.width, this.radius = 8});

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 1;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: [p.surfaceAlt, p.border, p.surfaceAlt],
            ),
          ),
        );
      },
    );
  }
}

class SkeletonCard extends StatelessWidget {
  final int lines;
  final double height;

  const SkeletonCard({super.key, this.lines = 3, this.height = 14});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            Skeleton(height: height, width: i == lines - 1 ? 120 : null),
            if (i != lines - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Staggered fade + rise, so lists arrive rather than pop.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;

  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // Cap the stagger so a long list does not take seconds to settle.
    Future<void>.delayed(
      Duration(milliseconds: 40 * widget.index.clamp(0, 8)),
      () {
        if (mounted) _c.forward();
      },
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
            .animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Empty-state card used by every list.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 36, color: p.textTertiary),
          const SizedBox(height: 12),
          Text(title,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "just now" / "4m ago" / "2h ago" — the last-sync stamp.
String relativeTime(DateTime? then) {
  if (then == null) return '';
  final d = DateTime.now().difference(then);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

/// "Mar 28" — the short date format the cards and calendar use.
String shortDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
}

/// "8:45 AM" — clock format for the schedule.
String clockTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}
