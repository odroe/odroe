abstract final class SchedulerJobFlags {
  static const queued = 1 << 0;
  static const pre = 1 << 1;
  static const allowRecurse = 1 << 2;
  static const disposed = 1 << 3;
}

final class SchedulerJob {
  SchedulerJob(this.fn, {this.id});

  final num? id;
  final void Function() fn;
  int flags = 0;
}

final _queueJobs = <SchedulerJob>[];
int _flushIndex = -1;

final _pendingPostJobs = <SchedulerJob>[];
List<SchedulerJob>? _activePostJobs;
int _postFlushIndex = 0;

Future<void>? _flushFuture;

Future<void> nextTick([void Function()? fn]) {
  if (_flushFuture != null) {
    return _flushFuture!.then((_) => fn?.call());
  }

  return Future.microtask(() => fn?.call());
}

int findInsertionIndex(num id) {
  int start = _flushIndex + 1, end = _queueJobs.length;
  while (start < end) {
    final middle = (start + end) >>> 1;
    final middleJob = _queueJobs[middle];
    final middleJobId = getJobId(middleJob);

    if (middleJobId < id ||
        (middleJobId == id && middleJob.flags & SchedulerJobFlags.pre != 0)) {
      start = middle + 1;
    } else {
      end = middle;
    }
  }

  return start;
}

num getJobId(SchedulerJob job) {
  if (job.id != null) {
    return job.id!;
  } else if (job.flags & SchedulerJobFlags.pre != 0) {
    return -1;
  }

  return double.infinity;
}

void queueJob(SchedulerJob job) {
  if (job.flags & SchedulerJobFlags.queued != 0) return;

  final jobId = getJobId(job);
  final lastJob = _queueJobs.lastOrNull;
  if (lastJob == null ||
      (job.flags & SchedulerJobFlags.pre == 0 && jobId > getJobId(lastJob))) {
    _queueJobs.add(job);
  } else {
    _queueJobs.insert(findInsertionIndex(jobId), job);
  }

  job.flags |= SchedulerJobFlags.queued;
  queueFlush();
}

void queueFlush() {
  _flushFuture ??= Future.microtask(flushJobs);
}

void flushJobs() {
  try {
    for (_flushIndex = 0; _flushIndex < _queueJobs.length; _flushIndex++) {
      final job = _queueJobs.elementAtOrNull(_flushIndex);
      if (job == null || job.flags & SchedulerJobFlags.disposed != 0) {
        continue;
      } else if (job.flags & SchedulerJobFlags.allowRecurse != 0) {
        job.flags &= ~SchedulerJobFlags.queued;
      }

      job.fn();

      if (job.flags & SchedulerJobFlags.allowRecurse == 0) {
        job.flags &= ~SchedulerJobFlags.queued;
      }
    }
  } finally {
    for (; _flushIndex < _queueJobs.length; _flushIndex++) {
      _queueJobs.elementAtOrNull(_flushIndex)?.flags &=
          ~SchedulerJobFlags.queued;
    }

    _flushIndex = -1;
    _queueJobs.clear();

    flushPostJobs();
    _flushFuture = null;
    if (_queueJobs.isNotEmpty || _pendingPostJobs.isNotEmpty) {
      flushJobs();
    }
  }
}

void flushPostJobs() {
  if (_pendingPostJobs.isEmpty) {
    return;
  }

  final jobs = [..._pendingPostJobs];
  _pendingPostJobs.clear();

  if (_activePostJobs != null) {
    _activePostJobs!.addAll(jobs);
    return;
  }

  _activePostJobs = jobs;
  for (_postFlushIndex = 0; _postFlushIndex < jobs.length; _postFlushIndex++) {
    final job = jobs.elementAtOrNull(_postFlushIndex);
    if (job == null || job.flags & SchedulerJobFlags.disposed != 0) {
      continue;
    } else if (job.flags & SchedulerJobFlags.allowRecurse != 0) {
      job.flags &= ~SchedulerJobFlags.queued;
    }

    job.fn();
    if (job.flags & SchedulerJobFlags.allowRecurse == 0) {
      job.flags &= ~SchedulerJobFlags.queued;
    }
  }

  _activePostJobs = null;
  _postFlushIndex = 0;
}
