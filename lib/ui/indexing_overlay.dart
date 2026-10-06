import 'dart:ui';

import 'package:flutter/material.dart';

/// Full-screen blurred overlay with a centered progress card, shown while the
/// models load and screenshots are being indexed. Blocks all interaction.
class IndexingOverlay extends StatelessWidget {
  const IndexingOverlay({super.key, required this.progress});

  /// (done, total) while indexing, or null while getting ready.
  final (int, int)? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: ColoredBox(color: scheme.surface.withValues(alpha: 0.55)),
        ),
        Center(child: _ProgressCard(progress: progress)),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final (int, int)? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = this.progress;
    final fraction = progress == null || progress.$2 == 0
        ? null
        : progress.$1 / progress.$2;

    return Container(
      width: 320,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _PulsingBadge(),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              fraction == null
                  ? 'Getting things ready'
                  : 'Indexing your screenshots',
              key: ValueKey(fraction == null),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fraction == null
                ? 'Loading the on-device AI model…'
                : 'Making them searchable. This only happens once per screenshot.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: fraction == null
                ? LinearProgressIndicator(
                    minHeight: 8,
                    backgroundColor: scheme.surfaceContainerHighest,
                  )
                : TweenAnimationBuilder<double>(
                    tween: Tween(end: fraction),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
          ),
          if (progress != null && fraction != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${progress.$1} of ${progress.$2}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(fraction * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Gradient circle with a sparkle icon that gently "breathes".
class _PulsingBadge extends StatefulWidget {
  const _PulsingBadge();

  @override
  State<_PulsingBadge> createState() => _PulsingBadgeState();
}

class _PulsingBadgeState extends State<_PulsingBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: Tween(begin: 0.92, end: 1.06).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: scheme.onPrimary,
          size: 30,
        ),
      ),
    );
  }
}
