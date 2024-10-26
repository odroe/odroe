abstract interface class SchedulerJobFlags {
  static const queued = 1 << 0;
  static const pre = 1 << 1;
  static const allowRecurse = 1 << 2;
  static const disposed = 1 << 3;
}

main() {
  int flags = SchedulerJobFlags.queued;
  print(flags & SchedulerJobFlags.queued);
  print(flags & SchedulerJobFlags.pre);
  print(flags & SchedulerJobFlags.allowRecurse);
}
