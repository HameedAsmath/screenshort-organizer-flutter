import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../services/pool_service.dart';
import 'screenshot_actions.dart';
import 'screenshot_detail_screen.dart';
import 'screenshot_tile.dart';

/// All screenshots in one pool, most typical first.
class PoolDetailScreen extends ConsumerWidget {
  const PoolDetailScreen({super.key, required this.pool});

  final Pool pool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final screenshots = ref.watch(screenshotsProvider);
    final byId = {for (final s in screenshots) s['id'] as int: s};

    // Keep the pool's order (most typical first), skip deleted screenshots,
    // and attach each member's similarity to the center as 'score'
    final members = <Map>[];
    for (var i = 0; i < pool.memberIds.length; i++) {
      final row = byId[pool.memberIds[i]];
      if (row == null) continue; // deleted
      members.add({
        ...row,
        if (pool.memberScores.isNotEmpty) 'score': pool.memberScores[i],
      });
    }

    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 130).floor().clamp(2, 6);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pool.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${members.length} screenshot${members.length == 1 ? '' : 's'}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: members.isEmpty
          ? const Center(child: Text('This pool is empty'))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
              ),
              itemCount: members.length,
              itemBuilder: (context, index) {
                final screenshot = members[index];
                return ScreenshotTile(
                  key: ValueKey(screenshot['id']),
                  screenshot: screenshot,
                  index: index,
                  onTap: () => openScreenshotDetails(context, screenshot),
                  onDelete: () => confirmAndDelete(context, ref, screenshot),
                );
              },
            ),
    );
  }
}
