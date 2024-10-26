import 'dart:async';

abstract interface class SchedulerJobFlags {
  static const queued = 1 << 0;
  static const pre = 1 << 1;
  static const allowRecurse = 1 << 2;
  static const disposed = 1 << 3;
}

class SchedulerJob {
  SchedulerJob(this.fn, {this.id});

  final int? id;
  int flags = 0;
  final void Function() fn;
}

final queue = <SchedulerJob>[];
final pendingPostFlushJobs = <SchedulerJob>[];
List<SchedulerJob>? activePostFlushJobs;

int flushIndex = -1;
int postFlushIndex = 0;
Future<void>? currentFlushFuture;

Future<void> nextTick([FutureOr<void> Function()? fn]) {
  return Future.value(currentFlushFuture)
      .then((_) => fn?.call())
      .then((_) => {});
}

int getJobId(SchedulerJob job) {
  if (job.id == null) {
    if ((job.flags & SchedulerJobFlags.pre) == 0) {
      return -1;
    }
    return queue.length;
  }

  return job.id!;
}

int findInsertIndex(int id) {
  int start = flushIndex + 1;
  int end = queue.length;

  while (start < end) {
    final middle = (start + end) >> 1;
    final middleJob = queue[middle];
    final middleJobId = getJobId(middleJob);

    if (middleJobId < id ||
        (middleJobId == id && (middleJob.flags & SchedulerJobFlags.pre) == 0)) {
      start = middle + 1;
      continue;
    }

    end = middle;
  }

  return start;
}

void queueJob(SchedulerJob job) {
  if (job.flags & SchedulerJobFlags.queued == 0) {
    return;
  }

  final jobId = getJobId(job);
  final lastJob = queue.elementAtOrNull(queue.length - 1);

  if (lastJob == null ||
      (job.flags & SchedulerJobFlags.pre == 0 && jobId >= getJobId(lastJob))) {
    queue.add(job);
  } else {
    queue.insert(findInsertIndex(jobId), job);
  }

  job.flags |= SchedulerJobFlags.queued;
  queueFlush();
}

void queueFlush() {
  currentFlushFuture ??= Future.sync(flushJobs);
}

void flushJobs() {
  try {
    for (flushIndex = 0; flushIndex < queue.length; flushIndex++) {
      final job = queue.elementAtOrNull(flushIndex);
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
    for (; flushIndex < queue.length; flushIndex++) {
      queue.elementAtOrNull(flushIndex)?.flags &= ~SchedulerJobFlags.queued;
    }

    flushIndex = -1;
    queue.clear();

    flushPostJobs();
    currentFlushFuture = null;
    if (queue.isNotEmpty || pendingPostFlushJobs.isNotEmpty) {
      flushJobs();
    }
  }
}

void flushPostJobs() {
  if (pendingPostFlushJobs.isEmpty) return;

  final deduped = [...pendingPostFlushJobs.toSet()]
    ..sort((a, b) => getJobId(a) - getJobId(b));
  pendingPostFlushJobs.clear();

  if (activePostFlushJobs != null) {
    return activePostFlushJobs!.addAll(deduped);
  }

  activePostFlushJobs = deduped;
  for (postFlushIndex = 0;
      postFlushIndex < activePostFlushJobs!.length;
      postFlushIndex++) {
    final job = activePostFlushJobs!.elementAt(postFlushIndex);
    if (job.flags & SchedulerJobFlags.allowRecurse != 0) {
      job.flags &= ~SchedulerJobFlags.queued;
    }
    if (job.flags & SchedulerJobFlags.disposed == 0) {
      job.fn();
    }

    job.flags &= ~SchedulerJobFlags.queued;
  }

  activePostFlushJobs = null;
  postFlushIndex = 0;
}
