extension type const Flags._(int _) implements int {
  static const active = Flags._(1 << 0);
  static const running = Flags._(1 << 1);
  static const tracking = Flags._(1 << 2);
  static const notified = Flags._(1 << 3);
  static const dirty = Flags._(1 << 4);
  static const allowRecurse = Flags._(1 << 5);
  static const paused = Flags._(1 << 6);

  Flags operator |(int other) => Flags._(_ | other);
}
