import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'home_screen.dart';
import 'indexing_overlay.dart';
import 'pools_screen.dart';

/// Top-level layout: two tabs (Screenshots, Pools) with a bottom bar, plus the
/// indexing overlay on top of everything.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final init = ref.watch(dbInitProvider);
    final progress = ref.watch(importProgressProvider);
    ref.watch(poolsProvider); // start computing pools after startup
    final isIndexing = init.isLoading;

    return Stack(
      children: [
        Scaffold(
          body: IndexedStack(
            index: _tab,
            children: const [HomeScreen(), PoolsScreen()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) {
              FocusScope.of(context).unfocus(); // close the keyboard
              setState(() => _tab = i);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.photo_library_outlined),
                selectedIcon: Icon(Icons.photo_library_rounded),
                label: 'Screenshots',
              ),
              NavigationDestination(
                icon: Icon(Icons.bubble_chart_outlined),
                selectedIcon: Icon(Icons.bubble_chart_rounded),
                label: 'Pools',
              ),
            ],
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
}
