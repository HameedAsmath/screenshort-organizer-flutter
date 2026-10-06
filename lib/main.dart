import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import 'services/database_service.dart';
import 'services/photo_service.dart';

import 'services/embedding_service.dart';

import 'dart:async';

import 'services/screenshot_importer.dart';

import 'services/debug_tools.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

final screenshotsProvider = StateProvider<List<Map>>((ref) => []);
final searchQueryProvider = StateProvider<String>((ref) => '');
final importProgressProvider = StateProvider<(int, int)?>((ref) => null);

Timer? _searchDebounce;

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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screenshot Organizer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(dbInitProvider);
    final progress = ref.watch(importProgressProvider);
    final screenshots = ref.watch(screenshotsProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResults = ref.watch(searchResultsProvider);

    // Show search results if searching, otherwise show all
    final displayList = searchQuery.isEmpty
        ? screenshots
        : (searchResults.whenData((data) => data).value ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Screenshot Organizer'),
        actions: [
          if (progress != null)
            Center(
              child: Text('${progress.$1} / ${progress.$2}'),
            ), // progress.$1 is "done" and progress.$2 is "total"
          if (init.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by description...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                  ref.read(searchQueryProvider.notifier).state = value.trim();
                });
              },
            ),
          ),
        ),
      ),
      body: searchQuery.isNotEmpty && searchResults.hasError
          ? const Center(child: Text('Search failed. Please try again.'))
          : displayList.isEmpty
          ? Center(
              child: Text(
                searchQuery.isEmpty
                    ? 'No screenshots. Tap + to import.'
                    : 'No matches found',
              ),
            )
          : ListView.builder(
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                final screenshot = displayList[index];
                return Card(
                  margin: const EdgeInsets.all(8),
                  child: ListTile(
                    leading: screenshot['imagePath'] != null
                        ? Image.file(
                            File(screenshot['imagePath'] as String),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.image),
                    title: Text(screenshot['name'] as String),
                    subtitle: Text(
                      screenshot['score'] != null
                          ? 'score: ${(screenshot['score'] as double).toStringAsFixed(3)}'
                          : '${screenshot['collection'] as String} • ${screenshot['createdAt'] as String}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        final db = DatabaseService();
                        await db.deleteScreenshot(screenshot['id'] as int);
                        final updated = await db.getAllScreenshots();
                        ref.read(screenshotsProvider.notifier).state = updated;
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          print('Button tapped');
          final files = await PhotoService.pickMultiplePhotos();
          print('Selected ${files.length} photos');

          if (files.isEmpty) {
            print('No files selected');
            return;
          }

          try {
            final db = DatabaseService();

            for (var file in files) {
              print('Processing: ${file.path}');

              // Generate embedding
              print('Generating embedding...');
              final embedding = await EmbeddingService.generateImageEmbedding(
                file.path,
              );
              print('Embedding generated (dim: ${embedding.length})');

              final row = <String, dynamic>{
                'name': file.path.split('/').last,
                'collection': 'Uncategorized',
                'tags': '[]',
                'imagePath': file.path,
                'createdAt': DateTime.now().toString().split(' ')[0],
              };

              if (embedding.isEmpty) {
                // Save the photo anyway; reindexMissingEmbeddings() retries it on next launch.
                await db.insertScreenshot(row);
                print('⚠️ Saved without embedding, will retry on next launch');
              } else {
                await db.insertScreenshotWithEmbedding(row, embedding);
                print('✅ Saved with embedding');
              }
            }

            // Reload
            final updated = await db.getAllScreenshots();
            print('Total screenshots: ${updated.length}');

            ref.read(screenshotsProvider.notifier).state = updated;
            ref.read(searchQueryProvider.notifier).state = ''; // Clear search
          } catch (e) {
            print('Error saving: $e');
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
