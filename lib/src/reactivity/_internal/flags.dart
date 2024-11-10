abstract final class Flags {
  static const tracking = 1 << 0;
  static const dirty = 1 << 1;
  static const notified = 1 << 2;
  static const active = 1 << 3;
  static const paused = 1 << 4;
  static const running = 1 << 5;
  static const allowRecurse = 1 << 6;
}
