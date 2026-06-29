// dgvault — seed data for the demo vault (in-memory, encrypted via real KDBX).

import 'dart:typed_data';

import 'package:dgvault/core/core.dart';

KdbxHeader demoHeader(KdfParams params) => KdbxHeader(
      cipher: DatabaseCipher.aes256,
      compressed: true,
      masterSeed:
          Uint8List.fromList(List.generate(32, (i) => (i * 11 + 5) & 0xff)),
      encryptionIv:
          Uint8List.fromList(List.generate(16, (i) => (i * 13 + 7) & 0xff)),
      kdfParameters: KdfParameters.toVariantDictionary(
        params,
        Uint8List.fromList(List.generate(16, (i) => (i * 17 + 3) & 0xff)),
      ),
    );

Entry _entry(
  String uuid, {
  required String title,
  String? user,
  String? pass,
  String? url,
  String? notes,
  String? totp,
  List<String> tags = const [],
}) {
  final fields = <String, Field>{
    Field.title:
        Field(key: Field.title, value: InMemoryProtectedValue.plain(title)),
    if (user != null)
      Field.userName:
          Field(key: Field.userName, value: InMemoryProtectedValue.plain(user)),
    if (pass != null)
      Field.password:
          Field(key: Field.password, value: InMemoryProtectedValue(pass)),
    if (url != null)
      Field.url:
          Field(key: Field.url, value: InMemoryProtectedValue.plain(url)),
    if (notes != null)
      Field.notes:
          Field(key: Field.notes, value: InMemoryProtectedValue.plain(notes)),
    if (totp != null)
      'TOTP': Field(
          key: 'TOTP', value: InMemoryProtectedValue(totp, isProtected: true),),
  };
  return Entry(
      uuid: uuid,
      fields: fields,
      tags: tags,
      modified: DateTime.utc(2026, 6, 1),);
}

Database buildDemoDatabase() {
  final personal = Group(
    uuid: 'g-personal',
    name: 'Personal',
    entries: [
      _entry(
        'e1',
        title: 'GitHub',
        user: 'realytcracker',
        pass: 'h4ck-the-pl4net!',
        url: 'https://github.com',
        totp: 'JBSWY3DPEHPK3PXP',
        tags: ['dev', 'vip'],
      ),
      _entry(
        'e2',
        title: 'Proton Mail',
        user: 'ytcracker@proton.me',
        pass: 'correct-horse-battery',
        url: 'https://proton.me',
        tags: ['email'],
      ),
      _entry(
        'e3',
        title: 'Bank of Dystopia',
        user: '4815162342',
        pass: 'M0n3y\$tack5',
        url: 'https://bank.example',
        notes: 'security questions in the safe',
        tags: ['finance', 'vip'],
      ),
    ],
  );

  final work = Group(
    uuid: 'g-work',
    name: 'Work',
    entries: [
      _entry(
        'e4',
        title: 'AWS Console',
        user: 'svc-deploy',
        pass: 'AKIA-not-a-real-key',
        url: 'https://console.aws.amazon.com',
        tags: ['cloud', 'prod'],
      ),
      _entry(
        'e5',
        title: 'Jira',
        user: 'ytc',
        pass: 'tickets4dayz',
        url: 'https://jira.example',
      ),
    ],
  );

  final servers = Group(
    uuid: 'g-servers',
    name: 'Servers',
    entries: [
      _entry(
        'e6',
        title: 'prod-db-01',
        user: 'root',
        pass: 'r00t-on-prod-yikes',
        url: 'ssh://10.0.0.12',
        notes: 'rotate quarterly',
        tags: ['ssh', 'prod'],
      ),
      _entry(
        'e7',
        title: 'edge-router',
        user: 'admin',
        pass: 'changeme-please',
        url: 'https://192.168.1.1',
        tags: ['network'],
      ),
    ],
  );

  final root =
      Group(uuid: 'root', name: 'dgvault', groups: [personal, work, servers]);
  return Database(meta: DatabaseMeta(name: 'dgvault demo'), root: root);
}
