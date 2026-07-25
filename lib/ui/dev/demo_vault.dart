// dgvault — dev-only: seed a demo vault and stage a screen for store
// screenshots. Simulators can't script the file picker or taps, so like
// DGVAULT_OPEN_ABOUT this jumps straight to the state we want to capture:
//
//   flutter run --dart-define=DGVAULT_DEMO=<stage>
//
// Stages: vault (unlocked entry list), locked (unlock screen), detail
// (entry detail pushed), generator (generator sheet open). Without the
// dart-define the const is empty and this code is compiled out entirely.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/model/entry.dart';
import '../../core/model/field.dart';
import '../../core/model/group.dart';
import '../../core/model/protected_value.dart';
import '../screens/entry_detail.dart';
import '../screens/generator_sheet.dart';
import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';

Future<void> stageDemo(
  VaultController c,
  String stage,
  GlobalKey<NavigatorState> navKey,
) async {
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}${Platform.pathSeparator}personal.kdbx';
  // Recreate from scratch so repeated runs are deterministic.
  final f = File(path);
  if (f.existsSync()) f.deleteSync();
  await c.createNew(path, 'correct horse battery staple');
  _seed(c);
  await c.save();

  switch (stage) {
    case 'locked':
      await c.lock();
    case 'detail':
      final entry =
          c.rootGroup!.allEntries.firstWhere((e) => e.title == 'github');
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(
              backgroundColor: TermColors.surface,
              title: Text(
                entry.title ?? 'entry',
                style: mono(size: 15, color: TermColors.textBright),
              ),
            ),
            body: EntryDetailView(
              entry: entry,
              onEdit: () {},
              onDelete: () {},
              onMove: () {},
              onRestore: (_) {},
            ),
          ),
        ),
      );
    case 'generator':
      showGenerator(navKey.currentContext!);
  }
}

void _seed(VaultController c) {
  final root = c.rootGroup!;

  Field plain(String key, String v) =>
      Field(key: key, value: InMemoryProtectedValue.plain(v));
  Field secret(String key, String v) =>
      Field(key: key, value: InMemoryProtectedValue(v));

  Entry entry(
    String title,
    String user,
    String pw, {
    String? url,
    String? totp,
    String? notes,
  }) =>
      Entry(
        uuid: c.newUuid(),
        fields: {
          Field.title: plain(Field.title, title),
          Field.userName: plain(Field.userName, user),
          Field.password: secret(Field.password, pw),
          if (url != null) Field.url: plain(Field.url, url),
          if (totp != null) 'TOTP': secret('TOTP', totp),
          if (notes != null) Field.notes: plain(Field.notes, notes),
        },
        created: DateTime.utc(2026, 3, 14, 9, 26),
        modified: DateTime.utc(2026, 7, 1, 15, 9),
      );

  void put(Group g, Entry e) => c.addEntry(e, group: g);

  put(
    root,
    entry(
      'github',
      'ncognito',
      'tr0ub4dor&3-Kx9!m',
      url: 'https://github.com',
      totp: 'JBSWY3DPEHPK3PXP',
      notes: 'work + personal repos. recovery codes in the safe.',
    ),
  );
  put(
    root,
    entry(
      'gmail',
      'ncognito@gmail.com',
      r'vY7#pLq2$wDf8@zN',
      url: 'https://mail.google.com',
      totp: 'GEZDGNBVGY3TQOJQ',
    ),
  );
  put(
    root,
    entry(
      'proton mail',
      'ncognito@proton.me',
      'mK4!xVb9#sRt2&hJ',
      url: 'https://mail.proton.me',
    ),
  );

  final finance = c.addGroup('finance');
  put(
    finance,
    entry(
      'first national bank',
      'ncognito',
      r'Qw3$mZx7!vBn4#kL',
      url: 'https://firstnational.example.com',
      notes: 'wire limit \$10k/day. call to raise.',
    ),
  );
  put(
    finance,
    entry(
      'coinbase',
      'ncognito@gmail.com',
      'jH8&fDs3@mNv6!pQ',
      url: 'https://coinbase.com',
      totp: 'MFRGGZDFMZTWQ2LK',
    ),
  );

  final work = c.addGroup('work');
  put(
    work,
    entry(
      'aws console',
      'ncognito-admin',
      r'bV5#tGy8&wEr2$uI',
      url: 'https://console.aws.amazon.com',
      totp: 'NBSWY3DPO5XXE3DE',
    ),
  );
  put(
    work,
    entry(
      'corp vpn',
      'ncognito',
      'zX9!cAs4#dFg7&hK',
      notes: 'profile: split-tunnel. cert renews yearly.',
    ),
  );
  put(work, entry('jira', 'ncognito@corp.example', r'pO2$iUy6!tRe9#wQ'));

  final servers = c.addGroup('servers');
  put(
    servers,
    entry(
      'prod postgres',
      'dbadmin',
      'nM3&bVc8@xZa5!sD',
      url: 'psql://db01.internal:5432',
      notes: 'read replica: db02. failover runbook in wiki.',
    ),
  );
  put(
    servers,
    entry(
      'home router',
      'admin',
      r'gF6#hJk1&lQw4$eR',
      url: 'https://192.168.1.1',
    ),
  );
  put(servers, entry('ssh bastion', 'ncognito', 'yT7!uIo2#pAs5&dF'));

  final personal = c.addGroup('personal');
  put(
    personal,
    entry(
      'netflix',
      'ncognito@gmail.com',
      r'kL8$mNb3!vCx6#zQ',
      url: 'https://netflix.com',
    ),
  );
  put(
    personal,
    entry(
      'steam',
      'ncognito',
      'wE4&rTy7@uIo1!pS',
      url: 'https://store.steampowered.com',
      totp: 'KRSXG5CTMVRXEZLU',
    ),
  );
}
