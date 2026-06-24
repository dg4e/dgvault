# Generates an independent WebAuthn vector (ES256/P-256) for dgvault's RP-side
# verifier. Requires: pip install --user cbor2 cryptography
import json, hashlib, os, struct
import cbor2
from cryptography.hazmat.primitives.asymmetric import ec, utils
from cryptography.hazmat.primitives import hashes

OUT = os.path.join(os.path.dirname(__file__), 'es256_vector.json')
RP_ID = 'example.com'

priv = ec.generate_private_key(ec.SECP256R1())
nums = priv.public_key().public_numbers()
x = nums.x.to_bytes(32, 'big'); y = nums.y.to_bytes(32, 'big')

cose = {1: 2, 3: -7, -1: 1, -2: x, -3: y}        # EC2 / ES256 / P-256
cose_bytes = cbor2.dumps(cose)

cred_id = os.urandom(16)
aaguid = b'\x00' * 16
rp_hash = hashlib.sha256(RP_ID.encode()).digest()

def auth_data(flags, sign_count, attested=b''):
    return rp_hash + bytes([flags]) + struct.pack('>I', sign_count) + attested

# Registration: UP|UV|AT (0x45), attested credential data present
attested = aaguid + struct.pack('>H', len(cred_id)) + cred_id + cose_bytes
reg_auth = auth_data(0x45, 0, attested)
att_obj = cbor2.dumps({'fmt': 'none', 'attStmt': {}, 'authData': reg_auth})
client_create = json.dumps({'type': 'webauthn.create', 'challenge': 'cc', 'origin': 'https://example.com'}).encode()

# Assertion: UP|UV (0x05), signCount 7, sign authData || SHA256(clientDataJSON)
asrt_auth = auth_data(0x05, 7)
client_get = json.dumps({'type': 'webauthn.get', 'challenge': 'gg', 'origin': 'https://example.com'}).encode()
signed = asrt_auth + hashlib.sha256(client_get).digest()
der_sig = priv.sign(signed, ec.ECDSA(hashes.SHA256()))

vec = {
  'rpId': RP_ID,
  'attestationObject': att_obj.hex(),
  'clientDataJson_create': client_create.hex(),
  'assertion_authData': asrt_auth.hex(),
  'clientDataJson_get': client_get.hex(),
  'assertion_signature': der_sig.hex(),
  'credentialId': cred_id.hex(),
  'expected_signCount': 7,
}
with open(OUT, 'w') as f:
    json.dump(vec, f, indent=2)
print('wrote', OUT)
