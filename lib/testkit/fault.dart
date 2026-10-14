/// A deliberate fault for the Probe Test Kit canary: a scenario that must
/// FAIL when the fault is on, proving the kit can fail at all.
///
/// The switch works only in debug and test runs: `assert` bodies are removed
/// from profile and release builds, so on a phone the getter is always false.
/// Nothing in the app sets it; only `test/testkit` does.
class TestkitFault {
  TestkitFault._();

  static bool _countRunsTwice = false;

  /// When on, every finished run is counted twice in the player's stats.
  static bool get countRunsTwice {
    var on = false;
    assert(() {
      on = _countRunsTwice;
      return true;
    }());
    return on;
  }

  static set countRunsTwice(bool value) => _countRunsTwice = value;
}
