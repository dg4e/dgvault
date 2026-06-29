# Hand-builds a real KDBX 3.1 file (AES-256-CBC + AES-KDF + Salsa20 inner stream
# + gzip), then verifies pykeepass reads it. Requires: pip install --user
# pykeepass pycryptodomex. Run from the repo root.
import struct, hashlib, gzip, os, base64
from Cryptodome.Cipher import AES, Salsa20
from Cryptodome.Util.Padding import pad

OUT = os.path.join(os.path.dirname(__file__), 'reference_kdbx3.kdbx')
PASSWORD = b'kdbx3pass'

AES_CIPHER_UUID = bytes.fromhex('31c1f2e6bf714350be5805216afc5aff')
SALSA20_IV = bytes.fromhex('e830094b97205d2a')

master_seed = bytes(range(32))
transform_seed = bytes((i * 7 + 3) & 0xff for i in range(32))
enc_iv = bytes((i * 5 + 1) & 0xff for i in range(16))
protected_stream_key = bytes((i * 11 + 9) & 0xff for i in range(32))
stream_start = bytes((i * 3 + 13) & 0xff for i in range(32))
rounds = 6000

# ---- header (v3: 1-byte id, 2-byte LE length, data) ----
def field(fid, data):
    return bytes([fid]) + struct.pack('<H', len(data)) + data

header = struct.pack('<II', 0x9AA2D903, 0xB54BFB67) + struct.pack('<HH', 1, 3)  # minor=1, major=3
header += field(2, AES_CIPHER_UUID)
header += field(3, struct.pack('<I', 1))            # gzip
header += field(4, master_seed)
header += field(5, transform_seed)
header += field(6, struct.pack('<Q', rounds))
header += field(7, enc_iv)
header += field(8, protected_stream_key)
header += field(9, stream_start)
header += field(10, struct.pack('<I', 2))           # Salsa20
header += field(0, b'\r\n\r\n')

# ---- keys ----
composite = hashlib.sha256(hashlib.sha256(PASSWORD).digest()).digest()
t = composite
ecb = AES.new(transform_seed, AES.MODE_ECB)
for _ in range(rounds):
    t = ecb.encrypt(t)
transformed = hashlib.sha256(t).digest()
master_key = hashlib.sha256(master_seed + transformed).digest()

# ---- inner XML with a Salsa20-protected password ----
salsa = Salsa20.new(key=hashlib.sha256(protected_stream_key).new(hashlib.sha256(protected_stream_key).digest()).digest() if False else hashlib.sha256(protected_stream_key).digest(), nonce=SALSA20_IV)
def protect(plntext):
    return base64.b64encode(salsa.encrypt(plntext.encode())).decode()

pw_protected = protect('s3cret-v3')  # consumes keystream in document order
xml = (
 '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
 '<KeePassFile><Meta><Generator>fixture</Generator><DatabaseName>v3db</DatabaseName>'
 '<Binaries/></Meta><Root><Group><UUID>cm9vdA==</UUID><Name>Root</Name><IconID>48</IconID>'
 '<Group><UUID>c3ViMw==</UUID><Name>Sub3</Name><IconID>48</IconID>'
 '<Entry><UUID>ZTE=</UUID><IconID>0</IconID>'
 '<String><Key>Title</Key><Value>Acme v3</Value></String>'
 '<String><Key>UserName</Key><Value>alice3</Value></String>'
 '<String><Key>URL</Key><Value>https://v3.example</Value></String>'
 f'<String><Key>Password</Key><Value Protected="True">{pw_protected}</Value></String>'
 '</Entry></Group></Group></Root></KeePassFile>'
).encode()

payload = gzip.compress(xml)

# ---- hashed block stream ----
def hashed_blocks(data):
    out = b''
    out += struct.pack('<I', 0) + hashlib.sha256(data).digest() + struct.pack('<I', len(data)) + data
    out += struct.pack('<I', 1) + bytes(32) + struct.pack('<I', 0)  # terminator
    return out

plaintext = stream_start + hashed_blocks(payload)
ciphertext = AES.new(master_key, AES.MODE_CBC, enc_iv).encrypt(pad(plaintext, 16))

with open(OUT, 'wb') as f:
    f.write(header + ciphertext)
print('wrote', OUT, os.path.getsize(OUT), 'bytes')

# ---- verify pykeepass reads it (independent validation that it's valid KDBX3) ----
from pykeepass import PyKeePass
kp = PyKeePass(OUT, password='kdbx3pass')
print('pykeepass version', kp.version, 'enc', kp.encryption_algorithm)
e = kp.entries[0]
print('title', repr(e.title), 'user', repr(e.username), 'pw', repr(e.password), 'url', repr(e.url))
