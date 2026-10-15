"""Send console commands to a running Dota 2 (started with -netconport 29000) and print the console output.
Speaks the VConsole2 protocol: 12-byte header = type[4] + version u16 + length u32 (big endian, incl. header)
+ handle u16. Console text arrives in PRNT packets (text starts 28 bytes into the payload).

Usage: python -I tools/netcon.py [--wait SECONDS] [--grep TEXT] [--all] "command 1" "command 2" ...
"""
import socket, struct, sys, time

args = sys.argv[1:]
wait, grep, show_all = 3.0, None, False
while args and args[0].startswith('--'):
    if args[0] == '--wait':
        wait = float(args[1]); args = args[2:]
    elif args[0] == '--grep':
        grep = args[1]; args = args[2:]
    elif args[0] == '--all':
        show_all = True; args = args[1:]
    else:
        break

sys.stdout.reconfigure(encoding='utf-8', errors='replace')


def packets(buf):
    pos = 0
    while pos + 12 <= len(buf):
        ptype = buf[pos:pos + 4]
        length = struct.unpack('>I', buf[pos + 6:pos + 10])[0]
        if length < 12 or pos + length > len(buf):
            break
        yield pos, ptype, buf[pos + 12:pos + length]
        pos += length
    return


def read_until(sock, deadline):
    buf = b''
    while time.time() < deadline:
        try:
            chunk = sock.recv(1 << 20)
            if not chunk:
                break
            buf += chunk
        except socket.timeout:
            pass
    return buf


s = socket.create_connection(('127.0.0.1', 29000), timeout=5)
s.settimeout(0.2)
backlog = read_until(s, time.time() + 1.0)   # banner, cvar list, old output
for cmd in args:
    data = cmd.encode('utf-8') + b'\0'
    s.sendall(b'CMND' + struct.pack('>HIH', 0x00d4, 12 + len(data), 0) + data)
    time.sleep(0.05)
buf = backlog + read_until(s, time.time() + wait)
s.close()

# print only output that arrived after the commands were sent (unless --all)
for pos, ptype, payload in packets(buf):
    if ptype != b'PRNT' or len(payload) <= 28 or (pos < len(backlog) and not show_all):
        continue
    text = payload[28:].split(b'\0', 1)[0].decode('utf-8', 'replace').rstrip('\n')
    for line in text.splitlines():
        if grep is None or grep in line:
            print(line)
