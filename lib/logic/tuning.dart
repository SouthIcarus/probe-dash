/// All gameplay numbers in one place, so balancing never means hunting
/// through code.
///
/// The world is measured in "units": the playfield is always
/// [worldHeight] units tall, and its width follows the screen's aspect
/// ratio. One unit scrolled = [metersPerUnit] meters of distance.
class Tuning {
  Tuning._();

  // World
  static const double worldHeight = 100;
  static const double metersPerUnit = 0.5;
  static const double probeXFraction = 0.28; // probe's x as a share of width

  // Probe physics (GAME-1)
  static const double fixedStep = 1 / 120; // seconds per physics step
  static const double gravity = 250; // units/s², downward
  static const double thrustVelocity = -88; // units/s, set on each tap
  static const double maxFallSpeed = 140; // units/s
  static const double probeRadius = 3;

  // Asteroid gates (GAME-2)
  static const double gateWidth = 11;
  static const double startGap = 34;
  static const double minGap = 24; // must stay >= 2.5 × probe height (15)
  static const double startSpacing = 58;
  static const double minSpacing = 44;
  static const double startSpeed = 38; // units/s
  static const double maxSpeed = 68;
  static const double edgeMargin = 6; // gap never touches the screen edge
  static const double maxGapShift = 28; // max change in gap centre between gates
  static const double nearMissDistance = 2.2; // units from a gate edge

  // Crystals
  static const double crystalRadius = 2.2;
  static const int nearMissBonus = 2;
  static const double magnetPickupEveryMeters = 400;
  static const double magnetRadius = 22;
  static const double magnetBaseSeconds = 3;

  // Revive (spec US-1)
  static const double reviveInvincibleSeconds = 2;
  static const double reviveClearAhead = 40; // units of gates removed ahead
  static const double shieldGraceBaseSeconds = 1.0;
  static const double shieldGracePerLevel = 0.1;

  // Head start (upgrade)
  static const double headStartMetersPerLevel = 50;
  static const double headStartSpeedFactor = 3;
}
