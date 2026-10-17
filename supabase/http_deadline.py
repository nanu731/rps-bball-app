"""Absolute request deadlines for bounded urllib transports; no retries or redirects."""
import http.client
import socket
import threading
import time
import urllib.request

class DeadlineSocket(socket.socket):
    """An absolute budget also bounds a peer that keeps sending tiny chunks."""
    @classmethod
    def wrap(cls, original, deadline):
        wrapped = cls(original.family, original.type, original.proto, fileno=original.detach())
        wrapped.deadline = deadline
        return wrapped

    def remaining(self):
        remaining = self.deadline - time.monotonic()
        if remaining <= 0: raise TimeoutError('Request deadline exceeded')
        self.settimeout(min(30, remaining))

    def recv_into(self, buffer, nbytes=0, flags=0):
        self.remaining()
        return super().recv_into(buffer, nbytes, flags)

    def sendall(self, data, flags=0):
        self.remaining()
        return super().sendall(data, flags)

class DeadlineConnection(http.client.HTTPConnection):
    def connect(self):
        deadline = time.monotonic() + self.timeout
        super().connect()
        self.sock = DeadlineSocket.wrap(self.sock, deadline)

class DeadlineHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, request):
        return self.do_open(DeadlineConnection, request)

class DeadlineHTTPSConnection(http.client.HTTPSConnection):
    """Keep TLS on the standard SSLSocket; interrupt only this request's socket."""
    def connect(self):
        deadline = time.monotonic() + self.timeout
        super().connect()
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            self.close()
            raise TimeoutError('Request deadline exceeded during connection')
        self.expired = threading.Event()
        connection = self.sock
        def expire():
            self.expired.set()
            try: connection.shutdown(socket.SHUT_RDWR)
            except OSError: pass
        self.timer = threading.Timer(remaining, expire)
        self.timer.daemon = True
        self.timer.start()

    def request(self, *args, **kwargs):
        try: return super().request(*args, **kwargs)
        except BaseException:
            if hasattr(self, 'timer'): self.timer.cancel()
            raise

    def getresponse(self):
        try: response = super().getresponse()
        except BaseException:
            if hasattr(self, 'timer'): self.timer.cancel()
            if getattr(self, 'expired', threading.Event()).is_set(): raise TimeoutError('Request deadline exceeded') from None
            raise
        read, close = response.read, response.close
        def bounded_read(*args, **kwargs):
            try:
                result = read(*args, **kwargs)
            except BaseException:
                if self.expired.is_set(): raise TimeoutError('Request deadline exceeded') from None
                raise
            if self.expired.is_set(): raise TimeoutError('Request deadline exceeded')
            return result
        def finish():
            self.timer.cancel()
            close()
        response.read, response.close = bounded_read, finish
        return response

class DeadlineHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, request):
        return self.do_open(DeadlineHTTPSConnection, request, context=self._context)
