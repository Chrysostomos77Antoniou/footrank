import 'package:flutter/foundation.dart';

/// What a screen knows about one list it fetches: the last answer, whether a
/// newer one is on its way, and how the last attempt failed.
///
/// It exists to get two things right that a bare `FutureBuilder` gets wrong:
///
/// * A refresh keeps showing the previous answer until the new one arrives, so
///   pulling to refresh (or retrying after a hiccup) never blanks the screen
///   and brings a skeleton back. [clear] is for the other case: the old answer
///   belongs to something else now (a different team is selected), so showing
///   it would be wrong.
/// * An answer that arrives after a newer request was started, or after
///   [clear], is dropped. Switch teams quickly and the first team's slow reply
///   can never overwrite the second team's list.
///
/// Because the answer lives here and not in a widget, switching tabs or
/// rebuilding the screen never makes it load again or flash a placeholder.
class Reloadable<T> {
  T? _data;
  Object? _error;
  bool _loading = false;
  int _generation = 0;

  /// The last answer, or null when there is none yet.
  T? get data => _data;

  /// How the last attempt failed; null after a success.
  Object? get error => _error;

  /// True while a request is in flight.
  bool get isLoading => _loading;

  /// The last attempt failed and nothing is being retried right now.
  bool get hasFailed => _error != null && !_loading;

  /// Forgets the answer and the error, and drops any reply still on its way.
  void clear() {
    _generation++;
    _data = null;
    _error = null;
    _loading = false;
  }

  /// Fetches again with [fetch]. Never throws: a failure is kept in [error]
  /// (and the previous [data], if any, stays). [onChanged] runs when loading
  /// starts and when the reply lands -- the screen's `setState`.
  Future<void> reload(
    Future<T> Function() fetch,
    VoidCallback onChanged,
  ) async {
    final generation = ++_generation;
    _loading = true;
    onChanged();
    try {
      final value = await fetch();
      if (generation != _generation) return;
      _data = value;
      _error = null;
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    }
    _loading = false;
    onChanged();
  }
}
