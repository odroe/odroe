from pathlib import Path
import json, os, queue, re, shutil, signal, subprocess, sys, tempfile, threading, time

root = Path(__file__).resolve().parents[2]
dart = shutil.which('dart')
flutter = shutil.which('flutter')
log = sys.stdout

def run(args, cwd, timeout=240):
    log.write('\nCOMMAND ' + repr(args) + '\n'); log.flush()
    process = subprocess.Popen(args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    finally:
        stop(process)
    if code: raise RuntimeError(f'Command exited {code}: {args}')

def stop(process):
    # The session/group can outlive its leader, so process.poll() alone is not
    # evidence that the server and SQLite descendants have stopped.
    def group_has_live_members():
        process.poll()  # Reap our leader before inspecting its process group.
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return False
        if sys.platform != 'linux' or not Path('/proc').is_dir():
            return True
        # Linux containers may leave orphaned zombies in the group. They no
        # longer run or own sockets/SQLite handles. Check only this group's
        # state records, never another process's command line or environment.
        for entry in Path('/proc').iterdir():
            if not entry.name.isdecimal():
                continue
            try:
                if os.getpgid(int(entry.name)) != process.pid:
                    continue
                fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
                # A zombie group leader can still have live worker threads.
                # /proc/pid/stat fields 3, 5 and 20: state, PGID, thread count.
                if int(fields[2]) == process.pid and (
                    fields[0] not in ('Z', 'X', 'x') or int(fields[17]) > 1
                ):
                    return True
            except (ProcessLookupError, FileNotFoundError):
                continue
            except (OSError, ValueError, IndexError):
                # An unreadable owned member is not evidence of termination.
                return True
        return False

    def signal_group(value):
        try:
            os.killpg(process.pid, value)
        except ProcessLookupError:
            pass

    def wait_for_group(seconds):
        deadline = time.monotonic() + seconds
        while group_has_live_members():
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.05)
        return True

    signal_group(signal.SIGTERM)
    if wait_for_group(10):
        return
    signal_group(signal.SIGKILL)
    if not wait_for_group(5):
        raise TimeoutError('Consumer process group did not terminate')

class Server:
    def __init__(self, args, cwd, db):
        env = dict(os.environ, ODROE_HOST='127.0.0.1', ODROE_PORT='0', ODROE_SQLITE_PATH=str(db))
        self.process = subprocess.Popen(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, start_new_session=True)
        lines = queue.Queue()
        def read():
            for line in self.process.stdout:
                log.write(line); log.flush(); lines.put(line)
        threading.Thread(target=read, daemon=True).start()
        deadline = time.monotonic() + 120
        try:
            while time.monotonic() < deadline:
                if self.process.poll() is not None: raise RuntimeError('Server exited before listening')
                try: line = lines.get(timeout=1)
                except queue.Empty: continue
                match = re.search(r'http://127\.0\.0\.1:(\d+)', line)
                if match:
                    self.origin = match.group(0); return
            raise TimeoutError('Server did not become ready')
        except BaseException:
            stop(self.process); raise
    def close(self): stop(self.process)

probe = r"""import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:odroe/odroe.dart';
import 'package:odroe/rpc.dart';
import 'package:batch_consumer/routes.dart' as generated;

void main() {
  test('generated typed RPC reads persistent SQLite state', () async {
    final context = await AppContext.create([RpcModule.http(
      baseUri: Uri.parse(const String.fromEnvironment('ODROE_SMOKE_ORIGIN')),
    )]);
    try {
      final client = context.read(rpcClientKey);
      final state = File('smoke-state.json');
      if (const bool.fromEnvironment('ODROE_SMOKE_CREATE')) {
        final post = await generated.routes.createPost(client, (title: 'batch consumer post'));
        state.writeAsStringSync(jsonEncode({'id': post.id, 'title': post.title}));
      }
      final expected = jsonDecode(state.readAsStringSync()) as Map;
      final page = await generated.routes.listPosts(client, (cursor: null, limit: 20));
      expect(page.items.any((post) => post.id == expected['id'] &&
        post.title == expected['title']), isTrue);
      // ignore: avoid_print
      print('PERSISTENT_TYPED_RPC ${jsonEncode(expected)}');
    } finally {
      await context.dispose();
    }
  });
}
"""
def main():
    if dart is None or flutter is None:
        raise RuntimeError('Put the selected Flutter SDK on PATH before running this consumer.')
    try:
        with tempfile.TemporaryDirectory(prefix='odroe-batch-consumer-', dir='/tmp') as temp:
            base = Path(temp); project = base / 'consumer'; db = base / 'persistent.sqlite3'
            run([dart, 'run', 'odroe', 'create', str(project), '--platforms', 'web',
                 '--project-name', 'batch_consumer', '--odroe-path', str(root), '--offline'], root)
            run([dart, 'run', 'odroe', 'generate'], project)
            (project / 'test').mkdir(exist_ok=True)
            (project / 'test/fullstack_smoke_test.dart').write_text(probe)
            run([dart, 'format', 'test/fullstack_smoke_test.dart'], project)
            run([dart, 'analyze', '--fatal-infos'], project)
            for create in [True, False]:
                server = Server([dart, 'run', 'odroe', 'dev', '--server-only', '--host', '127.0.0.1', '--port', '0'], project, db)
                try:
                    run([flutter, 'test', '--no-pub', '--reporter', 'expanded',
                        '--dart-define=ODROE_SMOKE_ORIGIN='+server.origin,
                        '--dart-define=ODROE_SMOKE_CREATE='+str(create).lower(),
                        'test/fullstack_smoke_test.dart'], project)
                finally: server.close()
            run([dart, 'run', 'odroe', 'build', '--server-only'], project)
            deployed = base / 'relocated'; shutil.copytree(project / 'build/odroe/server', deployed)
            executable = deployed / 'bin/server'
            server = Server([str(executable)], base, db)
            try:
                run([flutter, 'test', '--no-pub', '--reporter', 'expanded',
                    '--dart-define=ODROE_SMOKE_ORIGIN='+server.origin,
                    '--dart-define=ODROE_SMOKE_CREATE=false', 'test/fullstack_smoke_test.dart'], project)
            finally: server.close()
            result = {'create': True, 'generate': True, 'analyze': True, 'typedRpc': True,
                'sqliteRestart': True, 'nativeBundle': True, 'relocatedBundle': True,
                'nativeLibraries': sorted(p.name for p in (deployed/'lib').iterdir()),
                'migrations': sorted(p.name for p in (deployed/'migrations').iterdir())}
            print(json.dumps(result))
        log.write('\nDisposable generated consumer, servers, database, and relocated bundle cleaned.\n')
    finally:
        log.flush()

if __name__ == '__main__':
    main()
