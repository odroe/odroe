final class Flag {
  const Flag._();
  static const running = 1 << 0;
  static const notified = 1 << 1;
  static const outdated = 1 << 2;
  static const disposed = 1 << 3;
  static const hasError = 1 << 4;
  static const tracking = 1 << 5;
}
