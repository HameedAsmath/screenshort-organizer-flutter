import 'package:flutter/material.dart';

import 'screenshot_image.dart';
import 'screenshot_info.dart';

/// Square grid tile: the screenshot, a delete button in the top-right corner,
/// and a match score badge while searching. Fades and scales in on first show.
class ScreenshotTile extends StatelessWidget {
  const ScreenshotTile({
    super.key,
    required this.screenshot,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  final Map screenshot;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = screenshot['score'] as double?;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      // Small stagger so the first screen of tiles ripples in.
      duration: Duration(milliseconds: 260 + (index % 12) * 35),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.94 + 0.06 * t, child: child),
      ),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: screenshotHeroTag(screenshot),
                child: ScreenshotImage(
                  path: screenshot['imagePath'] as String?,
                  cacheWidth: 400,
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: _DeleteButton(onPressed: onDelete),
              ),
              if (score != null)
                Positioned(left: 6, bottom: 6, child: _ScoreBadge(score)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge(this.score);

  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            score.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
