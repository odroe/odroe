import 'dart:async';
import 'dart:io';

/// Runs a test subprocess without leaving an unbounded timeout cleanup path.
Future<ProcessResult> runTestProcess(
  String executable,
  List<String> arguments, {
  required Duration timeout,
}) async {
  final process = await Process.start(executable, arguments);
  final output = StringBuffer();
  final errors = StringBuffer();
  final stdoutSubscription = process.stdout
      .transform(systemEncoding.decoder)
      .listen(output.write);
  final stderrSubscription = process.stderr
      .transform(systemEncoding.decoder)
      .listen(errors.write);
  final stdoutDone = stdoutSubscription.asFuture<void>();
  final stderrDone = stderrSubscription.asFuture<void>();
  final exitCode = process.exitCode;

  int? code;
  var timedOut = false;
  try {
    code = await exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    await terminateTestProcess(process, exitCode);
  }

  await Future.wait<void>(<Future<void>>[
    _settleOutput(stdoutSubscription, stdoutDone),
    _settleOutput(stderrSubscription, stderrDone),
  ]);
  if (timedOut) {
    throw TimeoutException(
      '$executable timed out after $timeout.\n'
      'stdout:\n$output\n'
      'stderr:\n$errors',
      timeout,
    );
  }
  return ProcessResult(
    process.pid,
    code!,
    output.toString(),
    errors.toString(),
  );
}

/// Stops [process] with bounded graceful and forceful waits.
Future<void> terminateTestProcess(
  Process process, [
  Future<int>? exitCode,
]) async {
  final done = exitCode ?? process.exitCode;
  process.kill(ProcessSignal.sigterm);
  if (await _exitsWithin(done, const Duration(seconds: 5))) return;
  process.kill(ProcessSignal.sigkill);
  await _exitsWithin(done, const Duration(seconds: 5));
}

Future<bool> _exitsWithin(Future<int> exitCode, Duration timeout) async {
  try {
    await exitCode.timeout(timeout);
    return true;
  } on TimeoutException {
    return false;
  }
}

Future<void> _settleOutput(
  StreamSubscription<String> subscription,
  Future<void> done,
) async {
  try {
    await done.timeout(const Duration(seconds: 5));
  } on Object {
    try {
      await subscription.cancel().timeout(const Duration(seconds: 1));
    } on Object {
      // The process and test timeout are already bounded.
    }
  }
}
