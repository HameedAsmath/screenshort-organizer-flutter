import 'dart:io';

import 'package:flutter/material.dart';

/// Shows an image file with a soft fade-in and a placeholder when the file
/// is missing. [cacheWidth] decodes a smaller copy, which keeps grids fast.
class ScreenshotImage extends StatelessWidget {
  const ScreenshotImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
  });

  final String? path;
  final BoxFit fit;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    final path = this.path;
    if (path == null || path.isEmpty) return const _Placeholder();

    return Image.file(
      File(path),
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          child: child,
        );
      },
      errorBuilder: (context, error, stackTrace) =>
          const _Placeholder(icon: Icons.broken_image_outlined),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.icon = Icons.image_outlined});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: scheme.outline)),
    );
  }
}
