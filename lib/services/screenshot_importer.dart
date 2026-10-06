import 'database_service.dart';
import 'embedding_service.dart';
import 'gallery_service.dart';

class ScreenshotImporter {
  /// Indexes gallery screenshots that aren't in the database yet, newest first.
  /// [onProgress] is called after each one with (done, total).
  /// [limit] caps how many to process (handy for testing).
  static Future<void> importNew({
    void Function(int done, int total)? onProgress,
    int? limit,
  }) async {
    final db = DatabaseService();

    final assets = await GalleryService.getAllScreenshots();
    final indexed = await db.getIndexedAssetIds();

    var todo = assets.where((a) => !indexed.contains(a.id)).toList();
    if (limit != null) todo = todo.take(limit).toList();
    print('📥 ${todo.length} new screenshots to index');
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < todo.length; i++) {
      final asset = todo[i];
      final file = await asset.file;
      if (file == null) continue; // file missing or not readable, so skip it

      final embedding = await EmbeddingService.generateImageEmbedding(
        file.path,
      );

      await db.insertScreenshot({
        'name': file.path.split('/').last,
        'collection': 'Uncategorized',
        'tags': '[]',
        'imagePath': file.path,
        'createdAt': asset.createDateTime.toString().split(' ')[0],
        'assetId': asset.id,
        // If the AI failed, save without an embedding; reindexMissingEmbeddings() retries later
        if (embedding.isNotEmpty) 'embedding': embedding.join(','),
      });

      onProgress?.call(i + 1, todo.length);
    }

    final seconds = stopwatch.elapsed.inSeconds;
    print('✅ Import finished: ${todo.length} screenshots in ${seconds}s');
  }
}
