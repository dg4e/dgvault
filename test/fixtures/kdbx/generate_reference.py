from pykeepass import create_database, PyKeePass
import os

path = 'test/fixtures/kdbx/reference_aes_argon2.kdbx'
if os.path.exists(path): os.remove(path)
kp = create_database(path, password='correct horse battery staple')
g = kp.add_group(kp.root_group, 'Sub Work')
e = kp.add_entry(g, 'Acme Corp', 'alice', 's3cret!', url='https://acme.example', notes='line1 line2')
kp.save()

kp2 = PyKeePass(path, password='correct horse battery staple')
print('version', kp2.version)
print('encryption', kp2.encryption_algorithm)
print('kdf', kp2.kdf_algorithm)
ent = kp2.entries[0]
print('title', repr(ent.title), 'user', repr(ent.username), 'pw', repr(ent.password))
print('size', os.path.getsize(path))
