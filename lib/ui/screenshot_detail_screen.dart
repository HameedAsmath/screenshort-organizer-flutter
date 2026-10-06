import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screenshot_actions.dart';
import 'screenshot_image.dart';
import 'screenshot_info.dart';

/// Full-screen view of one screenshot: pinch to zoom, tap to show/hide the
/// controls, details panel at the bottom.
class ScreenshotDetailScreen extends ConsumerStatefulWidget {
  const ScreenshotDetailScreen({super.key, required this.screenshot});

  final Map screenshot;

  @override
  ConsumerState<ScreenshotDetailScreen> createState() =>
      _ScreenshotDetailScreenState();
}

class _ScreenshotDetailScreenState
    extends ConsumerState<ScreenshotDetailScreen> {
  bool _showChrome = true;

  Future<void> _delete() async {
    final deleted = await confirmAndDelete(context, ref, widget.screenshot);
    if (deleted && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenshot = widget.screenshot;
    final info = ScreenshotInfo.fromRow(screenshot);
    const chromeDuration = Duration(milliseconds: 220);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // The screenshot, as big as the screen allows.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showChrome = !_showChrome),
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(
                    child: Hero(
                      tag: screenshotHeroTag(screenshot),
                      child: ScreenshotImage(
                        path: screenshot['imagePath'] as String?,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Top bar: back + delete.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: AnimatedOpacity(
                  opacity: _showChrome ? 1 : 0,
                  duration: chromeDuration,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            _CircleButton(
                              icon: Icons.arrow_back_rounded,
                              tooltip: 'Back',
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const Spacer(),
                            _CircleButton(
                              icon: Icons.delete_outline_rounded,
                              tooltip: 'Remove',
                              onPressed: _delete,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom details panel.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: AnimatedSlide(
                  offset: _showChrome ? Offset.zero : const Offset(0, 0.3),
                  duration: chromeDuration,
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _showChrome ? 1 : 0,
                    duration: chromeDuration,
                    child: _DetailsPanel(info: info, screenshot: screenshot),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.info, required this.screenshot});

  final ScreenshotInfo info;
  final Map screenshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final score = screenshot['score'] as double?;
    final collection = screenshot['collection'] as String?;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  info.title,
                  style: textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.dateLabel,
                  style: textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (collection != null && collection.isNotEmpty)
                      _Chip(icon: Icons.folder_outlined, label: collection),
                    if (score != null)
                      _Chip(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Match ${score.toStringAsFixed(2)}',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  info.name,
                  style: textTheme.bodySmall?.copyWith(color: Colors.white38),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.14),
      ),
    );
  }
}
