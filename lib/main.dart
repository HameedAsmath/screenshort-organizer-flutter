import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import 'services/database_service.dart';
import 'services/photo_service.dart';

import 'services/embedding_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EmbeddingService.initialize();
  runApp(const ProviderScope(child: MyApp()));
}

final screenshotsProvider = StateProvider<List<Map>>((ref) => []);
final searchQueryProvider = StateProvider<String>((ref) => '');

final dbInitProvider = FutureProvider<void>((ref) async {
  final db = DatabaseService();
  await db.reindexMissingEmbeddings();
  final screenshots = await db.getAllScreenshots();
  ref.read(screenshotsProvider.notifier).state = screenshots;
});

final searchResultsProvider = FutureProvider<List<Map>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  print('Searching for: "$query"');
  final textEmbedding = await EmbeddingService.generateTextEmbedding(query);
  final db = DatabaseService();
  final results = await db.searchByEmbedding(textEmbedding, topK: 5);

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
    ref.watch(dbInitProvider);
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
                ref.read(searchQueryProvider.notifier).state = value;
              },
            ),
          ),
        ),
      ),
      body: displayList.isEmpty
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
                      '${screenshot['collection'] as String} • ${screenshot['createdAt'] as String}',
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

              // Save with embedding
              await db.insertScreenshotWithEmbedding({
                'name': file.path.split('/').last,
                'collection': 'Uncategorized',
                'tags': '[]',
                'imagePath': file.path,
                'createdAt': DateTime.now().toString().split(' ')[0],
              }, embedding);

              print('✅ Saved with embedding');
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
