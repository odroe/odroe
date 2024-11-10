/// Internal flag to control tracking state
bool _shouldTrack = true;

/// Internal stack to maintain tracking state history
final _trackStack = <bool>[];

/// Whether tracking is currently enabled
///
/// ```dart
/// if (shouldTrack) {
///   // Perform tracking
/// }
/// ```
bool get shouldTrack => _shouldTrack;

/// Temporarily pauses tracking.
///
/// Saves the current tracking state and disables tracking until [resetTracking] is called.
///
/// ```dart
/// pauseTracking();
/// // Tracking is disabled
/// resetTracking(); // Restores previous state
/// ```
void pauseTracking() {
  _trackStack.add(shouldTrack);
  _shouldTrack = false;
}

/// Re-enables tracking.
///
/// Saves the current tracking state and enables tracking until [resetTracking] is called.
///
/// ```dart
/// enableTracking();
/// // Tracking is enabled
/// resetTracking(); // Restores previous state
/// ```
void enableTracking() {
  _trackStack.add(shouldTrack);
  _shouldTrack = true;
}

/// Resets the previous global tracking state.
///
/// Restores tracking to the most recently saved state. If there is no saved state,
/// tracking will be enabled.
///
/// ```dart
/// pauseTracking();
/// resetTracking(); // Restores tracking to previous state
/// ```
void resetTracking() {
  try {
    _shouldTrack = _trackStack.removeLast();
  } catch (_) {
    _shouldTrack = true;
  }
}
