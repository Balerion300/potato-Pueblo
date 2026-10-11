"""Independent loopback game/control/HTTP fixtures for packaged client checks."""
import http.server
import socketserver
import struct
import threading
import time
import zlib


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    block_on_close = False


class Fixture:
    def __init__(self):
        self.game_ready = threading.Event()
        self.control_ready = threading.Event()
        self.lock = threading.Lock()
        fixture = self

        class Game(socketserver.StreamRequestHandler):
            def handle(self):
                fixture.game = self.wfile
                fixture.game_ready.set()
                self.wfile.write(b'This world is Pueblo 1.10 Enhanced.\r\n</xch_mudtext><img xch_mode=purehtml><xch_page clear=text>\n')
                self.wfile.flush()
                for line in self.rfile:
                    if not fixture.control_ready.wait(5):
                        return
                    with fixture.lock:
                        fixture.control.write(line)
                        fixture.control.flush()

        class Control(socketserver.StreamRequestHandler):
            def handle(self):
                fixture.control = self.wfile
                fixture.control_ready.set()
                for line in self.rfile:
                    if not fixture.game_ready.wait(5):
                        return
                    with fixture.lock:
                        if line.rstrip() == b'PERF-FRAGMENT':
                            # Deliberately split inside UTF-8, ANSI and Pueblo.
                            payload = '\x1b[32mSnowman \u2603 and caf\u00e9\x1b[0m <b>fragmented</b>\r\nPERF-FRAGMENT-DONE\n'.encode()
                            for offset in range(0, len(payload), 3):
                                fixture.game.write(payload[offset:offset+3])
                                fixture.game.flush()
                                time.sleep(.002)
                            continue
                        fixture.game.write(line)
                        fixture.game.flush()

        def chunk(kind, data):
            return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))

        pixels = b''.join(b'\0' + b''.join(bytes((212, 176, 96) if 20 <= x < 280 and 20 <= y < 130 else (40, 80, 128)) for x in range(300)) for y in range(150))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 300, 150, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')

        class HTTP(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path != '/pic.png':
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header('Content-Type', 'image/png')
                self.send_header('Content-Length', str(len(png)))
                self.end_headers()
                self.wfile.write(png)

            def log_message(self, *args):
                pass

        self.game_server = Server(('127.0.0.1', 0), Game)
        self.control_server = Server(('127.0.0.1', 0), Control)
        self.http_server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), HTTP)
        self.servers = (self.game_server, self.control_server, self.http_server)

    def __enter__(self):
        for server in self.servers:
            threading.Thread(target=server.serve_forever, daemon=True).start()
        return self

    def environment(self):
        return dict(POTATO_FIXTURE_GAME_PORT=str(self.game_server.server_address[1]),
                    POTATO_FIXTURE_CONTROL_PORT=str(self.control_server.server_address[1]),
                    POTATO_FIXTURE_HTTP_URL=f'http://127.0.0.1:{self.http_server.server_address[1]}/pic.png')

    def __exit__(self, *args):
        for server in self.servers:
            server.shutdown()
            server.server_close()
