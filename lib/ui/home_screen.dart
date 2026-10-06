import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/database_service.dart';
import '../services/embedding_service.dart';
import '../services/photo_service.dart';
import 'indexing_overlay.dart';
import 'screenshot_actions.dart';
import 'screenshot_detail_screen.dart';
import 'screenshot_tile.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _importing = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // show/hide the clear button
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = value.trim();
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    setState(() {});
  }

  void _openDetails(Map screenshot) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) =>
            ScreenshotDetailScreen(screenshot: screenshot),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _importFromPicker() async {
    print('Button tapped');
    final files = await PhotoService.pickMultiplePhotos();
    print('Selected ${files.length} photos');

    if (files.isEmpty) {
      print('No files selected');
      return;
    }

    setState(() => _importing = true);
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
      _clearSearch();
    } catch (e) {
      print('Error saving: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final init = ref.watch(dbInitProvider);
    final progress = ref.watch(importProgressProvider);
    final screenshots = ref.watch(screenshotsProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final searchResults = ref.watch(searchResultsProvider);

    final isIndexing = init.isLoading;
    final isSearching = searchQuery.isNotEmpty;
    final isSearchLoading = isSearching && searchResults.isLoading;
    final displayList = isSearching
        ? (searchResults.value ?? const [])
        : screenshots;

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: Text(
              'Screenshots',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _SearchField(
                  controller: _searchController,
                  enabled: !isIndexing,
                  onChanged: _onSearchChanged,
                  onClear: _clearSearch,
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              _ResultHeader(
                count: displayList.length,
                query: isSearching ? searchQuery : null,
                indexError: init.hasError,
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: _buildContent(
                    displayList: displayList,
                    isSearching: isSearching,
                    isSearchLoading: isSearchLoading,
                    searchFailed: isSearching && searchResults.hasError,
                    searchQuery: searchQuery,
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: isIndexing
              ? null
              : FloatingActionButton(
                  tooltip: 'Add photos',
                  onPressed: _importing ? null : _importFromPicker,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _importing
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              strokeCap: StrokeCap.round,
                            ),
                          )
                        : const Icon(
                            Icons.add_photo_alternate_outlined,
                            key: ValueKey('add'),
                          ),
                  ),
                ),
        ),
        // Blurred, blocking overlay while models load / screenshots index.
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !isIndexing,
            child: AnimatedOpacity(
              opacity: isIndexing ? 1 : 0,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut,
              child: isIndexing
                  ? IndexingOverlay(progress: progress)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent({
    required List<Map> displayList,
    required bool isSearching,
    required bool isSearchLoading,
    required bool searchFailed,
    required String searchQuery,
  }) {
    if (searchFailed) {
      return const _EmptyState(
        key: ValueKey('error'),
        icon: Icons.error_outline_rounded,
        title: 'Search failed',
        message: 'Something went wrong. Please try again.',
      );
    }
    if (isSearchLoading && displayList.isEmpty) {
      return const _SearchingIndicator(key: ValueKey('searching'));
    }
    if (displayList.isEmpty) {
      return isSearching
          ? const _EmptyState(
              key: ValueKey('no-matches'),
              icon: Icons.search_off_rounded,
              title: 'No matches',
              message:
                  'Try describing what\'s in the screenshot, like "receipt", "chat" or "qr code".',
            )
          : const _EmptyState(
              key: ValueKey('empty'),
              icon: Icons.photo_library_outlined,
              title: 'No screenshots yet',
              message:
                  'Screenshots you take will show up here. You can also tap + to add photos.',
            );
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 130).floor().clamp(2, 6);

    return AnimatedOpacity(
      key: ValueKey(isSearching ? 'results-$searchQuery' : 'all'),
      opacity: isSearchLoading ? 0.5 : 1,
      duration: const Duration(milliseconds: 200),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemCount: displayList.length,
        itemBuilder: (context, index) {
          final screenshot = displayList[index];
          return ScreenshotTile(
            key: ValueKey(screenshot['id']),
            screenshot: screenshot,
            index: index,
            onTap: () => _openDetails(screenshot),
            onDelete: () => confirmAndDelete(context, ref, screenshot),
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search your screenshots…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}

class _ResultHeader extends StatelessWidget {
  const _ResultHeader({
    required this.count,
    required this.query,
    required this.indexError,
  });

  final int count;
  final String? query;
  final bool indexError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final text = query == null
        ? '$count screenshot${count == 1 ? '' : 's'}'
        : '$count match${count == 1 ? '' : 'es'} for "$query"';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: Text(
                text,
                key: ValueKey(text),
                style: style,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (indexError)
            Tooltip(
              message: 'Indexing stopped early. Restart the app to retry.',
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three dots that bounce in turn while a search is running.
class _SearchingIndicator extends StatefulWidget {
  const _SearchingIndicator({super.key});

  @override
  State<_SearchingIndicator> createState() => _SearchingIndicatorState();
}

class _SearchingIndicatorState extends State<_SearchingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) _dot(theme.colorScheme.primary, i),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Searching…',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color, int i) {
    // Each dot bounces during its own slice of the cycle, one after another.
    final phase = (_controller.value - i * 0.2) % 1.0;
    final t = phase < 0.5 ? math.sin(phase * 2 * math.pi) : 0.0; // 0 → 1 → 0
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Transform.translate(
        offset: Offset(0, -8 * t),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4 + 0.6 * t),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
