import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/database_service.dart';

/// Asks for confirmation, then removes the screenshot from the app.
/// Returns true if it was deleted.
Future<bool> confirmAndDelete(
  BuildContext context,
  WidgetRef ref,
  Map screenshot,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.delete_outline_rounded),
      title: const Text('Remove screenshot?'),
      content: const Text(
        'It will be removed from this app. The original stays in your gallery.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  final db = DatabaseService();
  await db.deleteScreenshot(screenshot['id'] as int);
  ref.read(screenshotsProvider.notifier).state = await db.getAllScreenshots();
  ref.invalidate(searchResultsProvider);
  return true;
}
