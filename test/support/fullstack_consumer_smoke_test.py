import importlib.util
import json
import io
import os
from pathlib import Path
import signal
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location(
    'consumer_smoke', Path(__file__).with_name('fullstack_consumer_smoke.py'))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class HostedCacheIsolationTest(unittest.TestCase):
    def exercise(self, stale_resolution, hosted_create=False, hosted_aot=False):
        with tempfile.TemporaryDirectory(prefix='odroe-hosted-cache-test-', dir='/tmp') as temp:
            old_cache = Path(temp) / 'existing-cache'
            seeded = old_cache / 'hosted/pub.dev/odroe-0.1.0-dev.1'
            seeded.mkdir(parents=True)
            marker = seeded / 'locally-seeded'
            marker.write_text('must not be consumed or deleted')
            calls = []
            class ReachedGeneration(Exception):
                pass
            def fake_run(args, cwd, timeout=240, env=None):
                calls.append((args, env))
                if args[1:3] == ['build', 'cli']:
                    self.assertTrue(hosted_aot)
                    self.assertIsNone(env)
                    self.assertEqual(cwd, smoke.root)
                    self.assertEqual(Path(args[-1]).name, 'candidate cli')
                    return
                self.assertIsNotNone(env)
                cache = Path(env['PUB_CACHE'])
                self.assertNotEqual(cache.resolve(), old_cache.resolve())
                self.assertEqual(env['PUB_HOSTED_URL'], 'https://pub.dev')
                if hosted_create and (args[1] == 'create' or args[3] == 'create'):
                    self.assertEqual(list(cache.iterdir()), [])
                    self.assertEqual(args[-2:], ['--version', '0.1.0-dev.1'])
                    if hosted_aot:
                        self.assertTrue(args[0].endswith('/candidate cli/bundle/bin/odroe'))
                        project = Path(args[2])
                    else:
                        self.assertEqual(args[1], '--packages=' + str(smoke.root / '.dart_tool/package_config.json'))
                        project = Path(args[4])
                    (project / '.dart_tool').mkdir(parents=True)
                    resolve(project, cache)
                elif args[1] == 'create':
                    self.assertEqual(list(cache.iterdir()), [])
                    project = Path(args[-1])
                    (project / '.dart_tool').mkdir(parents=True)
                elif args[1:3] == ['pub', 'add']:
                    resolve(Path(cwd), cache)
                elif args[3] == 'generate':
                    raise ReachedGeneration()
            def resolve(project, cache):
                target = seeded if stale_resolution else cache / 'hosted/pub.dev/odroe-0.1.0-dev.1'
                target.mkdir(parents=True, exist_ok=True)
                (project / '.dart_tool/package_config.json').write_text(json.dumps({
                    'packages': [{'name': 'odroe', 'rootUri': target.as_uri()}]}))
                (project / 'pubspec.lock').write_text('  odroe:\n    source: hosted\n    version: "0.1.0-dev.1"\n')
                (project / 'pubspec.yaml').write_text('name: batch_consumer\n')
            with mock.patch.dict(os.environ, PUB_CACHE=str(old_cache),
                    PUB_HOSTED_URL='https://local.invalid',
                    ODROE_CREATE_AOT='1' if hosted_aot else '',
                    ODROE_HOSTED_VERSION='' if hosted_create else '0.1.0-dev.1',
                    ODROE_CREATE_VERSION='0.1.0-dev.1' if hosted_create else ''), \
                    mock.patch.object(smoke, 'run', side_effect=fake_run), \
                    mock.patch.object(smoke, 'dart', 'dart'), \
                    mock.patch.object(smoke, 'flutter', 'flutter'), \
                    mock.patch.object(smoke, 'log', io.StringIO()) as output:
                if stale_resolution:
                    with self.assertRaisesRegex(RuntimeError, 'isolated official hosted cache'):
                        smoke.main()
                    self.assertNotIn('VERIFIED_HOSTED_ODROE', output.getvalue())
                else:
                    with self.assertRaises(ReachedGeneration):
                        smoke.main()
                    self.assertIn('VERIFIED_HOSTED_ODROE', output.getvalue())
                    if hosted_create:
                        self.assertEqual(len(calls), 3 if hosted_aot else 2)
                    else:
                        self.assertEqual(calls[-2][0][3:], ['init', '--full-stack'])
                cache = Path(next(env for _, env in calls if env)['PUB_CACHE'])
                self.assertFalse(cache.exists())
                self.assertEqual(marker.read_text(), 'must not be consumed or deleted')
                self.assertEqual(os.environ['PUB_CACHE'], str(old_cache))

    def test_rejects_preexisting_seeded_package(self):
        self.exercise(stale_resolution=True)

    def test_fresh_cache_reaches_installed_cli(self):
        self.exercise(stale_resolution=False)

    def test_hosted_create_rejects_seeded_resolution(self):
        self.exercise(stale_resolution=True, hosted_create=True)

    def test_hosted_create_uses_candidate_dispatcher_and_fresh_cache(self):
        self.exercise(stale_resolution=False, hosted_create=True)

    def test_aot_hosted_create_rejects_seeded_resolution(self):
        self.exercise(stale_resolution=True, hosted_create=True, hosted_aot=True)

    def test_aot_hosted_create_uses_built_cli_and_fresh_cache(self):
        self.exercise(stale_resolution=False, hosted_create=True, hosted_aot=True)


# This descendant both executes continuously and holds a live resource. Merely
# leaving a PID behind (as a zombie), or suspending a live child, is insufficient.
CHILD = r'''
import json, os, signal, socket, sys, time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
listener = socket.socket()
listener.bind(('127.0.0.1', 0))
listener.listen()
marker = Path(sys.argv[1])
heartbeat = marker.with_name('heartbeat')
with heartbeat.open('ab', buffering=0) as pulse:
    pulse.write(b'.')
    temporary = marker.with_suffix('.tmp')
    temporary.write_text(json.dumps({
        'pid': os.getpid(), 'group': os.getpgrp(),
        'port': listener.getsockname()[1]}))
    temporary.replace(marker)
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        pulse.write(b'.')
        time.sleep(0.02)
'''


# Linux can report a dead main thread as Z while another thread still executes.
# A real pthread fixture makes that case observable through the same heartbeat
# and listener checks, independently of stop()'s /proc interpretation.
THREADED_CHILD = r'''
#include <arpa/inet.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static char *marker_path;
static char *heartbeat_path;

static void *worker(void *unused) {
    (void)unused;
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (listener < 0 || bind(listener, (struct sockaddr *)&address,
            sizeof(address)) != 0 || listen(listener, 8) != 0) _exit(2);
    socklen_t length = sizeof(address);
    if (getsockname(listener, (struct sockaddr *)&address, &length) != 0) _exit(3);
    int pulse = open(heartbeat_path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (pulse < 0 || write(pulse, ".", 1) != 1) _exit(4);
    char *temporary = malloc(4096);
    if (temporary == NULL) _exit(5);
    if (snprintf(temporary, 4096, "%s.tmp", marker_path) >= 4096) _exit(6);
    FILE *ready = fopen(temporary, "w");
    if (ready == NULL) _exit(7);
    fprintf(ready, "{\"pid\":%ld,\"group\":%ld,\"port\":%u}",
            (long)getpid(), (long)getpgrp(), (unsigned)ntohs(address.sin_port));
    if (fclose(ready) != 0 || rename(temporary, marker_path) != 0) _exit(8);
    free(temporary);
    struct timespec start, now, pause = {0, 20000000};
    if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) _exit(9);
    do {
        if (write(pulse, ".", 1) != 1) _exit(10);
        nanosleep(&pause, NULL);
        if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) _exit(11);
    } while (now.tv_sec - start.tv_sec < 120);
    close(pulse);
    close(listener);
    return NULL;
}

int main(int argc, char **argv) {
    if (argc != 3) return 12;
    marker_path = argv[1];
    heartbeat_path = argv[2];
    signal(SIGTERM, SIG_IGN);
    pthread_t thread;
    if (pthread_create(&thread, NULL, worker, NULL) != 0) return 13;
    pthread_exit(NULL);
}
'''


def _ready(marker):
    deadline = time.monotonic() + 5
    while not marker.exists():
        if time.monotonic() >= deadline:
            raise AssertionError('Owned descendant never became ready')
        time.sleep(0.02)
    return json.loads(marker.read_text())


def _assert_running(marker, child):
    heartbeat = marker.with_name('heartbeat')
    before = heartbeat.stat().st_size
    deadline = time.monotonic() + 2
    while heartbeat.stat().st_size == before:
        if time.monotonic() >= deadline:
            raise AssertionError('Owned descendant heartbeat never advanced')
        time.sleep(0.02)
    with socket.create_connection(('127.0.0.1', child['port']), timeout=1):
        pass


def _assert_resources_stopped(marker, child):
    heartbeat = marker.with_name('heartbeat')
    before = heartbeat.stat().st_size
    time.sleep(0.3)
    if heartbeat.stat().st_size != before:
        raise AssertionError('Owned descendant still executes after cleanup')
    try:
        connection = socket.create_connection(
            ('127.0.0.1', child['port']), timeout=1)
    except ConnectionRefusedError:
        return
    else:
        connection.close()
        raise AssertionError('Owned descendant still holds its listening socket')


def _kill_group(group):
    try:
        os.killpg(group, signal.SIGKILL)
    except ProcessLookupError:
        pass


def _bounded_call(action):
    errors = []

    def call():
        try:
            action()
        except BaseException as error:
            errors.append(error)

    worker = threading.Thread(target=call, daemon=True)
    worker.start()
    worker.join(timeout=20)
    if worker.is_alive():
        raise AssertionError('Consumer cleanup did not return within 20 seconds')
    if errors:
        raise errors[0]


def _linux_zombie_fixture(temp):
    # Only this isolated supervisor becomes a subreaper; the test runner and
    # system-wide reaping policy are untouched. Do not reap the adopted child
    # until stop() has had to contend with the deliberately retained zombie.
    import ctypes

    libc = ctypes.CDLL(None, use_errno=True)
    if libc.prctl(36, 1, 0, 0, 0) != 0:  # PR_SET_CHILD_SUBREAPER
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))

    def terminate_supervisor(_signal, _frame):
        raise SystemExit('Supervisor was terminated by its test runner')

    signal.signal(signal.SIGTERM, terminate_supervisor)
    marker = Path(temp) / 'child-ready'
    leader = (
        'import subprocess,sys; subprocess.Popen('
        '[sys.executable,"-c",' + repr(CHILD) + ',sys.argv[1]])')
    process = subprocess.Popen(
        [sys.executable, '-c', leader, str(marker)], start_new_session=True)
    try:
        (Path(temp) / 'owned-group').write_text(str(process.pid))
        if process.wait(timeout=5) != 0:
            raise AssertionError('Owned leader failed')
        child = _ready(marker)
        if child['group'] != process.pid:
            raise AssertionError('Descendant escaped the owned process group')
        _assert_running(marker, child)
        status_path = Path('/proc') / str(child['pid']) / 'status'
        status = status_path.read_text()
        if f'PPid:\t{os.getpid()}\n' not in status:
            raise AssertionError('Supervisor did not adopt its descendant')
        smoke.stop(process)
        _assert_resources_stopped(marker, child)
        status = status_path.read_text()
        state = next(line for line in status.splitlines()
                     if line.startswith('State:'))
        if state.split()[1] != 'Z':
            raise AssertionError('Fixture did not retain a zombie child')
        # The original predicate incorrectly considered this success evidence
        # of a live process. Keep the zombie unreaped for this assertion.
        os.killpg(process.pid, 0)
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        _kill_group(process.pid)
        process.wait(timeout=5)
        deadline = time.monotonic() + 5
        while True:
            try:
                adopted, _ = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                break
            if adopted == 0:
                if time.monotonic() >= deadline:
                    raise AssertionError('Supervisor could not reap its children')
                time.sleep(0.02)
    print('ZOMBIE_GROUP_STOPPED_AND_REAPED', flush=True)


@unittest.skipUnless(hasattr(os, 'killpg'), 'Requires POSIX process groups')
class ProcessGroupCleanupTest(unittest.TestCase):
    def test_stops_descendant_when_group_leader_has_exited(self):
        leader = (
            'import subprocess,sys; subprocess.Popen('
            '[sys.executable,"-c",' + repr(CHILD) + ',sys.argv[1]])')
        with tempfile.TemporaryDirectory(prefix='odroe-smoke-group-') as temp:
            marker = Path(temp) / 'child-ready'
            process = subprocess.Popen(
                [sys.executable, '-c', leader, str(marker)], start_new_session=True)
            try:
                self.assertEqual(process.wait(timeout=5), 0)
                child = _ready(marker)
                self.assertEqual(child['group'], process.pid)
                _assert_running(marker, child)
                _bounded_call(lambda: smoke.stop(process))
                _assert_resources_stopped(marker, child)
            finally:
                _kill_group(process.pid)
                process.wait(timeout=5)

    def test_failed_command_cleans_descendants_before_raising(self):
        leader = (
            'import json,os,socket,subprocess,sys,time\n'
            'open(sys.argv[2], "w").write(str(os.getpgrp()))\n'
            'subprocess.Popen([sys.executable,"-c",' + repr(CHILD) + ',sys.argv[1]])\n'
            'deadline = time.monotonic() + 5\n'
            'while not os.path.exists(sys.argv[1]):\n'
            '    if time.monotonic() >= deadline: sys.exit(8)\n'
            '    time.sleep(0.02)\n'
            'while os.path.getsize(os.path.join(os.path.dirname(sys.argv[1]), "heartbeat")) < 5:\n'
            '    if time.monotonic() >= deadline: sys.exit(9)\n'
            '    time.sleep(0.02)\n'
            'child = json.load(open(sys.argv[1]))\n'
            'socket.create_connection(("127.0.0.1", child["port"]), timeout=1).close()\n'
            'sys.exit(7)\n')
        with tempfile.TemporaryDirectory(prefix='odroe-smoke-command-') as temp:
            marker = Path(temp) / 'child-ready'
            group_marker = Path(temp) / 'owned-group'
            try:
                with self.assertRaisesRegex(RuntimeError, 'Command exited 7'):
                    _bounded_call(lambda: smoke.run(
                        [sys.executable, '-c', leader, str(marker), str(group_marker)], temp,
                        timeout=5))
                child = _ready(marker)
                _assert_resources_stopped(marker, child)
            finally:
                if group_marker.exists():
                    _kill_group(int(group_marker.read_text()))

    @unittest.skipUnless(sys.platform.startswith('linux'),
                         'Requires Linux PR_SET_CHILD_SUBREAPER and /proc')
    def test_returns_with_a_zombie_only_group_and_reaps_owned_children(self):
        with tempfile.TemporaryDirectory(prefix='odroe-smoke-zombie-') as temp:
            launcher = (
                'import runpy,sys; module = runpy.run_path(sys.argv[1]); '
                'module["_linux_zombie_fixture"](sys.argv[2])')
            supervisor = subprocess.Popen(
                [sys.executable, '-c', launcher, str(Path(__file__).resolve()), temp],
                start_new_session=True, stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True)
            try:
                output, _ = supervisor.communicate(timeout=40)
                self.assertEqual(supervisor.returncode, 0, output)
                self.assertIn('ZOMBIE_GROUP_STOPPED_AND_REAPED', output)
            finally:
                group_marker = Path(temp) / 'owned-group'
                if group_marker.exists():
                    _kill_group(int(group_marker.read_text()))
                if supervisor.poll() is None:
                    supervisor.terminate()
                    try:
                        supervisor.wait(timeout=6)
                    except subprocess.TimeoutExpired:
                        _kill_group(supervisor.pid)
                        supervisor.wait(timeout=5)
                supervisor.stdout.close()

    @unittest.skipUnless(sys.platform.startswith('linux'),
                         'Requires Linux thread state reporting in /proc')
    def test_kills_live_worker_after_main_thread_has_exited(self):
        compiler = (shutil.which('cc') or shutil.which('gcc')
                    or shutil.which('clang'))
        if compiler is None:
            self.skipTest('Requires a C compiler with pthread support')
        with tempfile.TemporaryDirectory(prefix='odroe-smoke-thread-') as temp:
            source = Path(temp) / 'threaded_child.c'
            executable = Path(temp) / 'threaded_child'
            marker = Path(temp) / 'child-ready'
            source.write_text(THREADED_CHILD)
            compiled = subprocess.run(
                [compiler, '-pthread', '-Wall', '-Wextra', str(source),
                 '-o', str(executable)], capture_output=True, text=True,
                timeout=20)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            process = subprocess.Popen(
                [str(executable), str(marker), str(marker.with_name('heartbeat'))],
                start_new_session=True)
            try:
                child = _ready(marker)
                self.assertEqual(child['pid'], process.pid)
                self.assertEqual(child['group'], process.pid)
                status_path = Path('/proc') / str(process.pid) / 'status'
                deadline = time.monotonic() + 5
                while True:
                    fields = dict(line.split(':', 1)
                                  for line in status_path.read_text().splitlines())
                    if (fields['State'].split()[0] == 'Z'
                            and int(fields['Threads']) > 1):
                        break
                    if time.monotonic() >= deadline:
                        self.fail('Fixture never retained a dead main thread and live worker')
                    time.sleep(0.02)
                self.assertIsNone(process.poll())
                _assert_running(marker, child)
                _bounded_call(lambda: smoke.stop(process))
                _assert_resources_stopped(marker, child)
                self.assertEqual(process.wait(timeout=5), -signal.SIGKILL)
            finally:
                _kill_group(process.pid)
                process.wait(timeout=5)

    def test_tolerates_a_group_that_already_disappeared(self):
        process = subprocess.Popen(
            [sys.executable, '-c', 'pass'], start_new_session=True)
        self.assertEqual(process.wait(timeout=5), 0)
        _bounded_call(lambda: smoke.stop(process))
        _bounded_call(lambda: smoke.stop(process))


if __name__ == '__main__':
    unittest.main()
