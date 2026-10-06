import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/database_service.dart';
import 'services/debug_tools.dart';
import 'services/embedding_service.dart';
import 'services/screenshot_importer.dart';

final screenshotsProvider = StateProvider<List<Map>>((ref) => []);
final searchQueryProvider = StateProvider<String>((ref) => '');
final importProgressProvider = StateProvider<(int, int)?>((ref) => null);

final dbInitProvider = FutureProvider<void>((ref) async {
  final db = DatabaseService();

  // 1. Show saved screenshots immediately
  ref.read(screenshotsProvider.notifier).state = await db.getAllScreenshots();

  // 2. Load models and retry any screenshots missing an embedding
  await EmbeddingService.initialize();
  await db.reindexMissingEmbeddings();

  // 3. Import new screenshots from the gallery
  await ScreenshotImporter.importNew(
    onProgress: (done, total) async {
      ref.read(importProgressProvider.notifier).state = (done, total);
      // Refresh the list every 10 screenshots so new ones appear as we go
      if (done % 10 == 0 || done == total) {
        ref.read(screenshotsProvider.notifier).state = await db
            .getAllScreenshots();
      }
    },
  );

  ref.read(importProgressProvider.notifier).state = null;
  ref.read(screenshotsProvider.notifier).state = await db.getAllScreenshots();
  await DebugTools.abTestLatest('juice'); // TEMPORARY: diagnostics
});

final searchResultsProvider = FutureProvider<List<Map>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  print('Searching for: "$query"');
  final textEmbedding = await EmbeddingService.generateTextEmbedding(query);
  if (textEmbedding.isEmpty) {
    throw Exception('Could not process search text');
  }
  final db = DatabaseService();
  final results = await db.searchByEmbedding(textEmbedding);

  print('Found ${results.length} results');
  return results;
});
