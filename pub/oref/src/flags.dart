/// Oref flags mask bits.
abstract final class Flags {
  const Flags._();
  static const running = 1 << 0;
  static const tarcking = 1 << 1;
  static const notified = 1 << 2;
  static const dirty = 1 << 3;
  static const active = 1 << 4;
  static const paused = 1 << 6;
  static const allowRecurse = 1 << 7;
}
