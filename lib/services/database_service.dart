import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

import 'embedding_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> getDatabase() async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'screenshot_organizer.db');

      return await openDatabase(
        path,
        version: 3, // ← CHANGE FROM 1 TO 3
        onCreate: _createTables,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      print('Database error: $e');
      rethrow;
    }
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS screenshots (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      collection TEXT,
      tags TEXT,
      imagePath TEXT,
      createdAt TEXT,
      embedding TEXT
    )
  '''); // ← ADDED embedding TEXT
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE screenshots ADD COLUMN imagePath TEXT');
      } catch (e) {
        print('Column already exists: $e');
      }
    }

    if (oldVersion < 3) {
      // ← ADD THIS
      try {
        await db.execute('ALTER TABLE screenshots ADD COLUMN embedding TEXT');
      } catch (e) {
        print('Column already exists: $e');
      }
    }
  }

  Future<int> insertScreenshot(Map<String, dynamic> screenshot) async {
    final db = await getDatabase();
    return await db.insert('screenshots', screenshot);
  }

  Future<List<Map<String, dynamic>>> getAllScreenshots() async {
    final db = await getDatabase();
    return await db.query('screenshots');
  }

  Future<int> insertScreenshotWithEmbedding(
    Map<String, dynamic> screenshot,
    List<double> embedding,
  ) async {
    final db = await getDatabase();
    screenshot['embedding'] = embedding.join(',');
    return await db.insert('screenshots', screenshot);
  }

  Future<List<Map<String, dynamic>>> searchByEmbedding(
    List<double> queryEmbedding, {
    int topK = 5,
  }) async {
    final db = await getDatabase();
    final all = await db.query('screenshots');

    final results = <(Map<String, dynamic>, double)>[];

    for (var screenshot in all) {
      final embeddingStr = screenshot['embedding'] as String?;
      if (embeddingStr == null || embeddingStr.isEmpty) continue;

      final embedding = embeddingStr
          .split(',')
          .map((s) => double.parse(s))
          .toList();
      final similarity = EmbeddingService.cosineSimilarity(
        queryEmbedding,
        embedding,
      );
      results.add((screenshot, similarity));
    }

    results.sort((a, b) => b.$2.compareTo(a.$2));
    return results.take(topK).map((r) => r.$1).toList();
  }

  Future<int> deleteScreenshot(int id) async {
    final db = await getDatabase();
    return await db.delete('screenshots', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllScreenshots() async {
    final db = await getDatabase();
    await db.delete('screenshots');
  }
}
