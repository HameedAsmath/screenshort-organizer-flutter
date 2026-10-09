import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/database_service.dart';
import 'services/embedding_service.dart';
import 'services/screenshot_importer.dart';

import 'services/pool_namer.dart';
import 'services/pool_service.dart';
import 'services/vector_math.dart';

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

/// Personal pools, computed once the startup work (embeddings, import) is done.
final poolsProvider = FutureProvider<List<Pool>>((ref) async {
  // Wait for dbInitProvider to finish before clustering
  await ref.watch(dbInitProvider.future);

  final all = await DatabaseService().getAllEmbeddings();
  final ids = [for (final e in all) e.$1];
  final vectors = [for (final e in all) VectorMath.normalize(e.$3)];
  final nameById = {for (final e in all) e.$1: e.$2};

  final sw = Stopwatch()..start();
  final k = PoolService.chooseK(vectors.length);
  final result = await PoolService.clusterInBackground(vectors, k);
  final clustered = PoolService.buildPools(ids, vectors, result);
  final pools = await PoolNamer.nameAll(clustered, nameById);
  print(
    '🧩 ${pools.length} pools ready in ${sw.elapsedMilliseconds} ms (k=$k)',
  );

  // TEMPORARY: list them so we can check the result
  for (final p in pools) {
    final examples = p.memberIds
        .take(3)
        .map((id) => nameById[id])
        .join('  ·  ');
    final avg = p.memberScores.isEmpty
        ? '  -  '
        : (p.memberScores.reduce((a, b) => a + b) / p.size).toStringAsFixed(2);
    print(
      '🧩 ${p.name.padRight(32)} ${p.size.toString().padLeft(3)}  tight $avg │ $examples',
    );
  }

  return pools;
});
