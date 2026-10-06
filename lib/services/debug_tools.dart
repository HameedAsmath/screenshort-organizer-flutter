import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'embedding_service.dart';

import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Temporary tools for finding problems. Not used by the app itself.
class DebugTools {
  /// Health check for stored embeddings:
  ///  1. counts: total, missing, and duplicate embeddings
  ///  2. for [sample] random screenshots: stored vs freshly computed
  ///     embedding similarity (should be ~1.000)
  static Future<void> checkEmbeddings({int sample = 10}) async {
    final db = await DatabaseService().getDatabase();

    Future<int> count(String sql) async =>
        Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;

    // --- 1. Counts ---
    final total = await count('SELECT COUNT(*) FROM screenshots');
    final missing = await count(
      "SELECT COUNT(*) FROM screenshots WHERE embedding IS NULL OR embedding = ''",
    );
    final distinct = await count(
      "SELECT COUNT(DISTINCT embedding) FROM screenshots WHERE embedding IS NOT NULL AND embedding != ''",
    );
    print(
      '🩺 rows=$total  withEmbedding=${total - missing}  missing=$missing  distinct=$distinct',
    );
    if (distinct < total - missing) {
      print('🩺 ❌ Some screenshots share the exact same embedding!');
    }

    // --- 2. Stored vs fresh ---
    final rows = await db.rawQuery(
      "SELECT name, imagePath, embedding FROM screenshots "
      "WHERE embedding IS NOT NULL AND embedding != '' "
      "ORDER BY RANDOM() LIMIT $sample",
    );
    for (final row in rows) {
      final stored = (row['embedding'] as String)
          .split(',')
          .map(double.parse)
          .toList();
      final fresh = await EmbeddingService.generateImageEmbedding(
        row['imagePath'] as String,
      );
      final sim = EmbeddingService.cosineSimilarity(stored, fresh);
      final flag = sim < 0.99 ? '  ❌ MISMATCH' : '';
      print('🩺 ${sim.toStringAsFixed(3)}  ${row['name']}$flag');
    }
    print('🩺 Check finished');
  }

  /// Finds screenshots that share an identical embedding, and checks each one
  /// against a freshly computed embedding.
  ///  ✅ = the stored embedding really is this image (images look the same)
  ///  ❌ = the stored embedding belongs to a different image (bug)
  static Future<void> checkDuplicates() async {
    final db = await DatabaseService().getDatabase();
    final rows = await db.rawQuery('''
      SELECT name, embedding FROM screenshots
      WHERE embedding IN (
        SELECT embedding FROM screenshots
        WHERE embedding IS NOT NULL AND embedding != ''
        GROUP BY embedding
        HAVING COUNT(*) > 1
      )
      ORDER BY embedding
    ''');
    print('🩺 ${rows.length} screenshots are in duplicate groups');

    // Need imagePath too, look it up by name
    String? lastEmbedding;
    var group = 0;
    var wrong = 0;
    for (final row in rows) {
      final stored = row['embedding'] as String;
      if (stored != lastEmbedding) {
        group++;
        lastEmbedding = stored;
      }

      final pathRows = await db.query(
        'screenshots',
        columns: ['imagePath'],
        where: 'name = ?',
        whereArgs: [row['name']],
        limit: 1,
      );
      final path = pathRows.first['imagePath'] as String;

      final fresh = await EmbeddingService.generateImageEmbedding(path);
      final sim = EmbeddingService.cosineSimilarity(
        stored.split(',').map(double.parse).toList(),
        fresh,
      );
      final ok = sim >= 0.99;
      if (!ok) wrong++;
      print(
        '🩺 group $group  ${sim.toStringAsFixed(3)} ${ok ? '✅' : '❌ WRONG'}  ${row['name']}',
      );
    }
    print('🩺 Duplicate check finished: $group groups, $wrong wrong');
  }

  /// Saves exactly what the model "sees" (the 224x224 crop) as a PNG next to
  /// the database, and prints facts about the original image.
  static Future<void> saveModelView(String imagePath, String outName) async {
    final outPath = '${await getDatabasesPath()}/$outName';

    final info = await Isolate.run(() {
      final image = img.decodeImage(File(imagePath).readAsBytesSync());
      if (image == null) return 'decode FAILED';

      // Same resize + crop as EmbeddingService._preprocessImage
      final resized = image.width < image.height
          ? img.copyResize(
              image,
              width: 224,
              interpolation: img.Interpolation.cubic,
            )
          : img.copyResize(
              image,
              height: 224,
              interpolation: img.Interpolation.cubic,
            );
      final cropped = img.copyCrop(
        resized,
        x: (resized.width - 224) ~/ 2,
        y: (resized.height - 224) ~/ 2,
        width: 224,
        height: 224,
      );
      File(outPath).writeAsBytesSync(img.encodePng(cropped));

      // Brightness range of the crop (same min and max means one flat color)
      num minV = double.infinity, maxV = -double.infinity;
      for (final p in cropped) {
        final v = p.luminance;
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      return 'original ${image.width}x${image.height}, '
          'format=${image.format}, channels=${image.numChannels}, '
          'crop brightness $minV..$maxV';
    });

    print('🩺 $outName  ←  ${imagePath.split('/').last}');
    print('🩺    $info');
  }

  /// For [query]: prints the top 5 results, then where [name] ranks
  /// among ALL screenshots (ignores the 0.25 cutoff).
  static Future<void> rankOf(String query, String name) async {
    final db = await DatabaseService().getDatabase();
    final q = await EmbeddingService.generateTextEmbedding(query);

    final rows = await db.rawQuery(
      "SELECT name, embedding FROM screenshots "
      "WHERE embedding IS NOT NULL AND embedding != ''",
    );
    final scored = [
      for (final r in rows)
        (
          r['name'] as String,
          EmbeddingService.cosineSimilarity(
            q,
            (r['embedding'] as String).split(',').map(double.parse).toList(),
          ),
        ),
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    print('🩺 "$query" top 5:');
    for (final s in scored.take(5)) {
      print('🩺    ${s.$2.toStringAsFixed(3)}  ${s.$1}');
    }

    final i = scored.indexWhere((s) => s.$1 == name);
    if (i < 0) {
      print('🩺 $name is not in the database');
    } else {
      print(
        '🩺 $name → rank ${i + 1} of ${scored.length}, '
        'score ${scored[i].$2.toStringAsFixed(3)}',
      );
    }
  }

  /// A/B test on the most recently added image:
  ///  - computes its embedding the OLD way (main thread) and the NEW way
  ///    (background isolates), and compares them (should be ~1.000)
  ///  - shows how well each matches [query], and where it ranks overall
  static Future<void> abTestLatest(String query) async {
    final db = await DatabaseService().getDatabase();
    final latest = (await db.rawQuery(
      'SELECT name, imagePath FROM screenshots ORDER BY id DESC LIMIT 1',
    )).first;
    final path = latest['imagePath'] as String;
    print('🩺 A/B on: ${latest['name']}');

    final oldWay = await EmbeddingService.generateImageEmbedding(
      path,
      background: false,
    );
    final newWay = await EmbeddingService.generateImageEmbedding(
      path,
      background: true,
    );
    final q = await EmbeddingService.generateTextEmbedding(query);

    print(
      '🩺 old vs new similarity: '
      '${EmbeddingService.cosineSimilarity(oldWay, newWay).toStringAsFixed(3)}  (should be ~1.000)',
    );
    print(
      '🩺 "$query" score  old: '
      '${EmbeddingService.cosineSimilarity(q, oldWay).toStringAsFixed(3)}  '
      'new: ${EmbeddingService.cosineSimilarity(q, newWay).toStringAsFixed(3)}',
    );

    await rankOf(query, latest['name'] as String);
  }
}
