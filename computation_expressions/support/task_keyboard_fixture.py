"""Exercise the actual stdin transport, including partial lines and stalled input."""
import argparse
import os
from pathlib import Path
import queue
import subprocess
import threading
import time


def check(args, mode):
    env = os.environ.copy()
    env.update(CE_KEYBOARD_TIMEOUT_MS='500' if mode == 'timeout' else '2500',
               CE_KEYBOARD_HEARTBEAT_MS='30', CE_KEYBOARD_SETTLE_MS='80')
    script = Path(__file__).resolve().parents[1] / 'examples/task_keyboard_demo.das'
    command = [args.daslang, str(script), '-no-module-cache']
    if args.jit:
        command += ['-jit', '-jit-no-cache']
    child = subprocess.Popen(command, env=env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = []
    incoming = queue.Queue()

    def reader():
        try:
            for line in iter(child.stdout.readline, b''):
                incoming.put(line.decode('utf-8', 'replace').rstrip('\r\n'))
        finally:
            incoming.put(None)

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    deadline = time.monotonic() + 20

    def receive():
        left = deadline - time.monotonic()
        if left <= 0:
            raise AssertionError(f'{mode}: watchdog expired: {lines}')
        line = incoming.get(timeout=left)
        if line is None:
            raise AssertionError(f'{mode}: premature process exit: {lines}')
        lines.append(line)
        return line

    def until(predicate):
        while not predicate():
            receive()

    def write(data):
        child.stdin.write(data)
        child.stdin.flush()

    try:
        until(lambda: any(x.startswith('READY ') for x in lines))
        # Deliberately withhold Enter and split a UTF-8 code point across writes.
        if mode in ('success', 'timeout'):
            write('Привет'.encode('utf-8')[:1])
        until(lambda: sum(x.startswith('HEARTBEAT=') for x in lines) >= 2)
        assert not any(x.startswith(('INPUT=', 'ERROR=')) or x in ('CANCELLED', 'TIMEOUT') for x in lines), lines
        if mode == 'success':
            write('Привет'.encode('utf-8')[1:] + b'\n')
            child.stdin.close()
            expected = 'INPUT=Привет'
        elif mode == 'cancel':
            write(b'/cancel\n')
            child.stdin.close()
            expected = 'CANCELLED'
        elif mode == 'timeout':
            expected = 'TIMEOUT'  # stdin remains open, partial input never gets Enter.
        elif mode == 'eof':
            child.stdin.close()
            expected = 'ERROR=task event source is closed'
        else:
            write(b'/quit\n')
            child.stdin.close()
            expected = 'QUIT'
        until(lambda: 'Task keyboard demo OK' in lines)
        assert child.wait(timeout=3) == 0, lines
        assert expected in lines, lines
        assert 'SUBSCRIPTIONS=0' in lines, lines
        if mode != 'quit':
            outcome = lines.index(expected)
            assert any(x.startswith('HEARTBEAT=') for x in lines[outcome + 1:]), lines
            assert any(x.startswith('BACKGROUND_AFTER_INPUT=') for x in lines), lines
        if mode != 'success':
            assert not any(x.startswith('INPUT=') for x in lines), lines
        print(f'Task keyboard {mode} OK: background progressed while waiting; subscriptions released', flush=True)
    finally:
        if not child.stdin.closed:
            try:
                child.stdin.close()
            except (BrokenPipeError, OSError):
                pass
        if child.poll() is None:
            child.kill()
            child.wait(timeout=3)
        thread.join(2)
        child.stdout.close()
        assert not thread.is_alive(), 'stdout reader leaked'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--daslang', required=True)
    ap.add_argument('--jit', action='store_true')
    args = ap.parse_args()
    for mode in ('success', 'cancel', 'timeout', 'eof', 'quit'):
        check(args, mode)
    print('Task keyboard checks OK')


if __name__ == '__main__':
    main()
