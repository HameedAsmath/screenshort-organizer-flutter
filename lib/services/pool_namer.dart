import 'embedding_service.dart';
import 'pool_service.dart';
import 'vector_math.dart';

/// Gives pools human names using CLIP (pool center vs. text labels)
/// plus the dominant source app from screenshot file names.
class PoolNamer {
  /// Candidate names. Each is embedded as "a screenshot of {label}".
  /// Add/remove labels freely to tune names for your screenshots.
  static const labels = [
    'chat conversations',
    'AI chatbot conversations',
    'social media posts',
    'memes',
    'quotes',
    'tweets',
    'job posts',
    'professional profiles',
    'online courses',
    'certificates',
    'online shopping products',
    'payment receipts',
    'bank transactions',
    'investment and stock charts',
    'food delivery orders',
    'recipes',
    'maps and directions',
    'train tickets and schedules',
    'bus and flight bookings',
    'hotel bookings',
    'cab rides',
    'event tickets',
    'phone calls',
    'dial pad',
    'home screen',
    'app settings',
    'notifications',
    'emails',
    'calendar events',
    'code',
    'error messages',
    'documents',
    'notes',
    'articles',
    'news',
    'videos',
    'movies and shows',
    'music',
    'games',
    'chess games',
    'sports scores',
    'photos of people',
    'nature photos',
    'quizzes',
    'ID cards',
    'QR codes',
    'OTP and verification codes',
    'login screens',
    'weather',
    'web pages',
    'search results',
    'dashboards and analytics',
    'spreadsheets',
    'presentations',
    'blank black screens',
  ];

  static List<List<double>>? _labelVectors; // computed once, then reused

  /// Embeds every label once (about 55 text runs, a few seconds).
  static Future<void> _prepare() async {
    if (_labelVectors != null) return;
    _labelVectors = [
      for (final label in labels)
        VectorMath.normalize(
          await EmbeddingService.generateTextEmbedding(
            'a screenshot of $label',
          ),
        ),
    ];
  }

  /// Names every pool (biggest first gets first pick). "Other" keeps its name.
  /// [fileNames] maps screenshot id → file name (for the source app).
  static Future<List<Pool>> nameAll(
    List<Pool> pools,
    Map<int, String> fileNames,
  ) async {
    await _prepare();
    final used = <String>{};
    final named = <Pool>[];
    for (final pool in pools) {
      if (pool.center == null) {
        named.add(pool); // "Other"
      } else {
        named.add(pool.withName(_bestName(pool, fileNames, used)));
      }
    }
    return named;
  }

  static String _bestName(
    Pool pool,
    Map<int, String> fileNames,
    Set<String> used,
  ) {
    // 1. Rank all labels by similarity to the pool's center, best first
    final center = pool.center!;
    final ranked = List.generate(labels.length, (i) => i)
      ..sort(
        (a, b) => VectorMath.dot(
          center,
          _labelVectors![b],
        ).compareTo(VectorMath.dot(center, _labelVectors![a])),
      );

    // 2. Is one app dominant in this pool?
    final app = _dominantApp(pool, fileNames);

    // 3. Take the best name that isn't used by a bigger pool yet
    for (final i in ranked.take(5)) {
      final label = _capitalize(labels[i]);
      final name = app == null ? label : '$app · $label';
      if (used.add(name)) return name; // add() returns false if already used
    }

    // 4. Very rare: all top 5 taken, so number it
    final base = _capitalize(labels[ranked.first]);
    var n = 2;
    while (!used.add('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  /// Android screenshot names end with the app: Screenshot_20260930-122156_GPay.png
  static final _appPattern = RegExp(r'^Screenshot_\d{8}-\d{6}[_.](.+?)\.\w+$');

  /// The app that most of the pool comes from, if it's at least [share] of it.
  static String? _dominantApp(
    Pool pool,
    Map<int, String> fileNames, {
    double share = 0.7,
  }) {
    final counts = <String, int>{};
    for (final id in pool.memberIds) {
      final match = _appPattern.firstMatch(fileNames[id] ?? '');
      if (match != null) {
        final app = match.group(1)!;
        counts[app] = (counts[app] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;

    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return top.value / pool.size >= share ? top.key : null;
  }

  static String _capitalize(String s) => s[0].toUpperCase() + s.substring(1);
}
