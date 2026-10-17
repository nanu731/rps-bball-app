"""Content-free, process-local evidence. No files, provider calls or crash reporting."""
import argparse
from collections import deque
from enum import Enum
import json
import queue
import sys
import threading
import time

class Category(str, Enum):
    FILE = 'file_processing'
    EXPORT = 'export_run'
    HEALTH = 'worker_status'

class Outcome(str, Enum):
    SUCCEEDED = 'succeeded'
    FAILED = 'failed'
    CANCELLED = 'cancelled'
    UNCONFIRMED = 'unconfirmed'

class Failure(str, Enum):
    NONE = 'none'
    DENIED = 'denied'
    INVALID = 'invalid'
    UNAVAILABLE = 'unavailable'
    CAPACITY = 'capacity'
    CANCELLED = 'cancelled'
    DISABLED = 'disabled'

class Diagnostics:
    """64 events/15min; <=32 emissions/min; one active and one queued sink item.

    External stderr capture retention belongs to the trusted operator. Sink errors
    never escape into application work; a blocked sink cannot grow the queue.
    """
    def __init__(self, sink=None, clock=time.monotonic):
        self.sink = sink if sink is not None else lambda line: print(line, file=sys.stderr)
        self.clock = clock
        self.lock = threading.Lock()
        self.events = deque(maxlen=64)
        self.discarded = self.suppressed = self.sink_failures = 0
        self.window = clock()
        self.emitted = 0
        self.output = queue.Queue(maxsize=1)
        self.idle = threading.Event(); self.idle.set()
        self.thread = None  # Lazy; status inspection alone creates no background work.

    def _expire(self, now):
        while self.events and now - self.events[0][0] >= 900:
            self.events.popleft(); self.discarded = min(9999, self.discarded + 1)

    def record(self, category, outcome, failure=Failure.NONE, *, seconds=0, attempts=1):
        # Reject arbitrary strings instead of attempting to scrub secrets after formatting.
        if not isinstance(category, Category) or not isinstance(outcome, Outcome) or not isinstance(failure, Failure):
            return
        try:
            duration = round(min(3600, max(0, float(seconds))) * 100) * 10
            event = dict(category=category.value, outcome=outcome.value, failure=failure.value,
                         duration_ms=duration, attempts=min(3, max(0, int(attempts))))
            with self.lock:
                now = self.clock(); self._expire(now)
                if len(self.events) == 64: self.discarded = min(9999, self.discarded + 1)
                self.events.append((now, event))
                if now - self.window >= 60: self.window, self.emitted = now, 0
                if self.emitted >= 32:
                    self.suppressed = min(9999, self.suppressed + 1); return
                if self.thread is None:
                    self.thread = threading.Thread(target=self._drain, daemon=True, name='safe-diagnostics')
                    self.thread.start()
                try: self.output.put_nowait(json.dumps(event, separators=(',', ':'), allow_nan=False))
                except queue.Full:
                    self.suppressed = min(9999, self.suppressed + 1); return
                self.idle.clear()
                self.emitted += 1
        except Exception:
            # A diagnostic allocation/encoding/clock failure cannot change the operation.
            return

    def _drain(self):
        while True:
            line = self.output.get()
            try: self.sink(line)
            except Exception:
                with self.lock: self.sink_failures = min(9999, self.sink_failures + 1)
            finally:
                with self.lock:
                    self.output.task_done()
                    if self.output.unfinished_tasks == 0: self.idle.set()

    def flush(self, timeout=0.05):
        return self.idle.wait(min(0.05, max(0, timeout)))

    def snapshot(self):
        with self.lock:
            self._expire(self.clock())
            return dict(events=[dict(e) for _, e in self.events], discarded=self.discarded,
                        suppressed=self.suppressed, sink_failures=self.sink_failures)

    def availability(self, *, enabled, configured):
        with self.lock:
            self._expire(self.clock())
            recent = [e for t, e in self.events if self.clock() - t < 60]
            unavailable = any(e['failure'] == Failure.UNAVAILABLE.value for e in recent)
        dependency = 'not_checked'
        if unavailable:
            dependency = 'recent_failure'
        # No passive report establishes current credentials, authority, capacity or $0 safety.
        state = 'disabled' if not enabled else 'configuration_unavailable' if not configured else 'downstream_unavailable' if dependency == 'recent_failure' else 'not_verified'
        return dict(liveness='alive', readiness=state, dependency=dependency, authorization='per_operation')

DIAGNOSTICS = Diagnostics()

class SafeArgumentParser(argparse.ArgumentParser):
    def error(self, message):
        self.exit(2, 'Invalid worker arguments. Use --help.\n')
