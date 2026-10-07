import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'pool_card.dart';
import 'pool_detail_screen.dart';

class PoolsScreen extends ConsumerWidget {
  const PoolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pools = ref.watch(poolsProvider);
    final screenshots = ref.watch(screenshotsProvider);

    // id → screenshot row, so each pool can find its cover image
    final byId = {for (final s in screenshots) s['id'] as int: s};

    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 180).floor().clamp(2, 5);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Text(
          'Pools',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: pools.when(
        data: (list) => list.isEmpty
            ? const Center(child: Text('No pools yet'))
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78, // a bit taller than wide
                ),
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final pool = list[i];
                  return PoolCard(
                    key: ValueKey(pool.name),
                    pool: pool,
                    cover: byId[pool.coverId],
                    index: i,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PoolDetailScreen(pool: pool),
                      ),
                    ),
                  );
                },
              ),
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(strokeCap: StrokeCap.round),
              const SizedBox(height: 16),
              Text(
                'Organizing your screenshots…',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        error: (e, _) => Center(child: Text('Could not build pools: $e')),
      ),
    );
  }
}
