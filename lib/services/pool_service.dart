import 'dart:math' as math;
import 'dart:isolate';

import 'vector_math.dart';

/// Result of k-means: which cluster each vector belongs to, plus each
/// cluster's center direction (length 1).
class KMeansResult {
  final List<int> assignments; // assignments[i] = cluster of vector i
  final List<List<double>> centers;
  final int iterations;

  const KMeansResult(this.assignments, this.centers, this.iterations);
}

class PoolService {
  /// Runs [kMeans] on a background isolate so the UI stays smooth.
  /// Kept as a separate small function so the closure only captures
  /// [vectors] and [k] (things that can be copied to another isolate).
  static Future<KMeansResult> kMeansInBackground(
    List<List<double>> vectors,
    int k,
  ) {
    return Isolate.run(() => kMeans(vectors, k));
  }

  /// Spherical k-means. [vectors] must already be normalized (length 1).
  /// A fixed [seed] gives the same clusters every time.
  static KMeansResult kMeans(
    List<List<double>> vectors,
    int k, {
    int seed = 42,
    int maxIterations = 30,
  }) {
    final n = vectors.length;
    if (n == 0) return const KMeansResult([], [], 0);
    k = math.min(k, n);
    final random = math.Random(seed);

    // --- Step A: k-means++ picks well-spread starting centers ---
    final centers = <List<double>>[
      List<double>.from(vectors[random.nextInt(n)]),
    ];
    // nearest[i] = similarity of vector i to its closest center so far
    final nearest = List<double>.filled(n, -1.0);
    while (centers.length < k) {
      final last = centers.last;
      final weights = List<double>.filled(n, 0.0);
      var total = 0.0;
      for (var i = 0; i < n; i++) {
        final s = VectorMath.dot(vectors[i], last);
        if (s > nearest[i]) nearest[i] = s;
        // Far from every center = higher chance to become the next center
        weights[i] = math.max(0.0, 1 - nearest[i]);
        total += weights[i];
      }
      if (total == 0) break; // every vector already sits on a center

      // Pick a vector at random, weighted by those distances
      var r = random.nextDouble() * total;
      var chosen = n - 1;
      for (var i = 0; i < n; i++) {
        r -= weights[i];
        if (r <= 0) {
          chosen = i;
          break;
        }
      }
      centers.add(List<double>.from(vectors[chosen]));
    }

    final assignments = List<int>.filled(n, -1);
    final dim = vectors.first.length;
    var iterations = 0;
    while (iterations < maxIterations) {
      iterations++;

      // --- Step B: each vector joins its most similar center ---
      var changed = 0;
      for (var i = 0; i < n; i++) {
        var best = 0;
        var bestScore = -2.0;
        for (var c = 0; c < centers.length; c++) {
          final s = VectorMath.dot(vectors[i], centers[c]);
          if (s > bestScore) {
            bestScore = s;
            best = c;
          }
        }
        if (assignments[i] != best) {
          assignments[i] = best;
          changed++;
        }
      }
      if (changed == 0) break; // stable: nobody moved

      // --- Step C: move each center to the middle of its members ---
      final sums = [for (final _ in centers) List<double>.filled(dim, 0.0)];
      final counts = List<int>.filled(centers.length, 0);
      for (var i = 0; i < n; i++) {
        VectorMath.addInto(sums[assignments[i]], vectors[i]);
        counts[assignments[i]]++;
      }
      for (var c = 0; c < centers.length; c++) {
        if (counts[c] > 0) centers[c] = VectorMath.normalize(sums[c]);
      }
    }

    return KMeansResult(assignments, centers, iterations);
  }

  /// How many pools to aim for: about sqrt(n / 2), between 4 and 20.
  /// 683 screenshots → 18.
  static int chooseK(int n) => math.sqrt(n / 2).round().clamp(4, 20);

  /// The center direction of a group: normalized sum of its members.
  static List<double> centerOf(List<int> members, List<List<double>> vectors) {
    final sum = List<double>.filled(vectors.first.length, 0.0);
    for (final i in members) {
      VectorMath.addInto(sum, vectors[i]);
    }
    return VectorMath.normalize(sum);
  }

  /// How tight a group is: average similarity of its members to the center.
  /// Near 1.0 = almost identical screenshots; lower = a looser mix.
  static double tightness(List<int> members, List<List<double>> vectors) {
    final center = centerOf(members, vectors);
    var total = 0.0;
    for (final i in members) {
      total += VectorMath.dot(vectors[i], center);
    }
    return total / members.length;
  }

  /// Bisecting k-means: keeps splitting loose groups in two (k-means with
  /// k = 2) until every group is tight enough or too small to split.
  /// Returns the result in the same shape as [kMeans], so [buildPools]
  /// works unchanged.
  static KMeansResult splitLooseGroups(
    List<List<double>> vectors,
    KMeansResult start, {
    double minTightness = 0.82,
    int minSize = 9,
  }) {
    // Turn the starting clusters into lists of member indexes
    final queue = <List<int>>[
      for (var c = 0; c < start.centers.length; c++)
        [
          for (var i = 0; i < vectors.length; i++)
            if (start.assignments[i] == c) i,
        ],
    ]..removeWhere((g) => g.isEmpty);

    final done = <List<int>>[];
    while (queue.isNotEmpty) {
      final group = queue.removeLast();

      // Tight enough, or too small to split into two real pools? Keep it.
      if (group.length < 2 * minSize ||
          tightness(group, vectors) >= minTightness) {
        done.add(group);
        continue;
      }

      // Split in two with k-means (k = 2) on just this group's vectors
      final sub = kMeans([for (final i in group) vectors[i]], 2);
      final a = <int>[];
      final b = <int>[];
      for (var j = 0; j < group.length; j++) {
        (sub.assignments[j] == 0 ? a : b).add(group[j]);
      }

      if (a.isEmpty || b.isEmpty) {
        done.add(group); // couldn't split it; keep as is
      } else {
        queue
          ..add(a)
          ..add(b); // check both halves again
      }
    }

    // Back to the KMeansResult shape: an assignment per vector + centers
    final assignments = List<int>.filled(vectors.length, -1);
    for (var g = 0; g < done.length; g++) {
      for (final i in done[g]) {
        assignments[i] = g;
      }
    }
    return KMeansResult(assignments, [
      for (final g in done) centerOf(g, vectors),
    ], start.iterations);
  }

  /// Full clustering on a background isolate: k-means, then split loose groups.
  static Future<KMeansResult> clusterInBackground(
    List<List<double>> vectors,
    int k,
  ) {
    return Isolate.run(() => splitLooseGroups(vectors, kMeans(vectors, k)));
  }

  /// Turns k-means output into pools, biggest first.
  /// [ids] and [vectors] must be in the same order that was clustered.
  /// Clusters smaller than [minSize] are collected into one "Other" pool.
  static List<Pool> buildPools(
    List<int> ids,
    List<List<double>> vectors,
    KMeansResult result, {
    int minSize = 9,
  }) {
    final groups = <(List<int>, List<double>)>[]; // (member indexes, center)
    final other = <int>[];

    for (var c = 0; c < result.centers.length; c++) {
      final center = result.centers[c];
      final members = [
        for (var i = 0; i < ids.length; i++)
          if (result.assignments[i] == c) i,
      ];
      if (members.isEmpty) continue;

      if (members.length < minSize) {
        other.addAll(members.map((i) => ids[i]));
        continue;
      }

      // Most typical first: highest similarity to the center
      members.sort(
        (a, b) => VectorMath.dot(
          vectors[b],
          center,
        ).compareTo(VectorMath.dot(vectors[a], center)),
      );
      groups.add((members, center));
    }

    groups.sort((a, b) => b.$1.length.compareTo(a.$1.length));

    return [
      for (var g = 0; g < groups.length; g++)
        Pool(
          name: 'Pool ${g + 1}',
          memberIds: [for (final i in groups[g].$1) ids[i]],
          memberScores: [
            for (final i in groups[g].$1)
              VectorMath.dot(vectors[i], groups[g].$2),
          ],
          center: groups[g].$2,
        ),
      if (other.isNotEmpty) Pool(name: 'Other', memberIds: other),
    ];
  }
}

/// One personal pool: a group of similar screenshots.
class Pool {
  final String name;
  final List<int> memberIds; // screenshot ids, most typical first
  final List<double> memberScores; // similarity of each member to the center
  final List<double>? center; // null for the "Other" pool

  const Pool({
    required this.name,
    required this.memberIds,
    this.memberScores = const [],
    this.center,
  });

  int get size => memberIds.length;

  /// The most typical screenshot represents the pool.
  int get coverId => memberIds.first;

  /// A copy of this pool with a different name.
  Pool withName(String newName) => Pool(
    name: newName,
    memberIds: memberIds,
    memberScores: memberScores,
    center: center,
  );
}
