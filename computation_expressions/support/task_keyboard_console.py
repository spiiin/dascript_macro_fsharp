"""Windows console frontend; the daScript scheduler never reads a terminal directly."""
import argparse
import os
import queue
import subprocess
import sys
import threading
import time


def normalise(text):
    # getwch exposes UTF-16 code units on Windows (including surrogate pairs).
    return text.encode('utf-16-le', 'surrogatepass').decode('utf-16-le', 'replace')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--daslang', required=True)
    ap.add_argument('--script', required=True)
    ap.add_argument('--timeout-ms', type=int, default=15000)
    ap.add_argument('--jit', action='store_true')
    args = ap.parse_args()
    if os.name != 'nt' or not sys.stdin.isatty() or not sys.stdout.isatty():
        ap.error('Run this launcher in an interactive Windows terminal, without redirection.')
    import msvcrt
    env = os.environ.copy()
    env['CE_KEYBOARD_TIMEOUT_MS'] = str(args.timeout_ms)
    command = [args.daslang, args.script, '-no-module-cache']
    if args.jit:
        command += ['-jit', '-jit-no-cache']
    child = subprocess.Popen(command, env=env, stdin=subprocess.PIPE,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             creationflags=subprocess.CREATE_NEW_PROCESS_GROUP)
    output = queue.Queue()

    def read_output():
        try:
            for line in iter(child.stdout.readline, b''):
                output.put(line.decode('utf-8', 'replace').rstrip('\r\n'))
        finally:
            child.stdout.close()

    reader = threading.Thread(target=read_output, daemon=True)
    reader.start()
    buffer = []
    width = 0
    submitted = False

    def clear():
        nonlocal width
        sys.stdout.write('\r' + ' ' * width + '\r')
        width = 0

    def redraw():
        nonlocal width
        if submitted:
            sys.stdout.flush()
            return
        text = 'input> ' + normalise(''.join(buffer))
        sys.stdout.write(text)
        sys.stdout.flush()
        width = len(text) * 2 + 4

    def drain():
        while True:
            try:
                line = output.get_nowait()
            except queue.Empty:
                break
            clear()
            print(line)
            redraw()

    def send(line):
        nonlocal submitted
        if submitted:
            return
        submitted = True
        try:
            child.stdin.write(normalise(line).encode('utf-8') + b'\n')
            child.stdin.flush()
        except (BrokenPipeError, OSError):
            if child.poll() is None:
                raise
        finally:
            try:
                child.stdin.close()
            except (BrokenPipeError, OSError):
                pass

    ignored_key = False
    interrupted_at = None
    print('One input: text + Enter. Esc/Ctrl+C cancels; /quit exits.')
    redraw()
    try:
        while child.poll() is None:
            try:
                drain()
                if not submitted and msvcrt.kbhit():
                    key = msvcrt.getwch()
                    if ignored_key:
                        ignored_key = False
                        continue
                    if key in ('\x00', '\xe0'):
                        ignored_key = True
                        continue
                    clear()
                    if key in ('\x1b', '\x03'):
                        buffer.clear()
                        send('/cancel')
                        print('[Cancellation requested]')
                    elif key in ('\r', '\n'):
                        line = ''.join(buffer)
                        buffer.clear()
                        send(line)
                        print('> ' + normalise(line))
                    elif key == '\b':
                        if buffer:
                            removed = buffer.pop()
                            if 0xDC00 <= ord(removed) <= 0xDFFF and buffer and 0xD800 <= ord(buffer[-1]) <= 0xDBFF:
                                buffer.pop()
                    elif ord(key) >= 32 and len(buffer) < 1024:
                        buffer.append(key)
                    redraw()
                if interrupted_at is not None and time.monotonic() - interrupted_at > 3:
                    raise TimeoutError('Child did not finish cancellation')
                time.sleep(.01)
            except KeyboardInterrupt:
                buffer.clear()
                send('/cancel')
                interrupted_at = time.monotonic()
        reader.join(2)
        drain()
        clear()
        return child.returncode
    finally:
        clear()
        try:
            if not child.stdin.closed:
                child.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        if child.poll() is None:
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.terminate()
                child.wait(timeout=3)
        reader.join(2)


if __name__ == '__main__':
    sys.exit(main())
