// dgvault — KeePass 2.x inner-XML codec (model ⇄ XML).
//
// This is the *inner* document of a KDBX file: the decrypted, decompressed XML
// tree KeePass stores inside the encrypted block. This codec maps it to/from the
// dgvault model so the KDBX reader/writer only has to handle the binary header,
// KDF, and cipher (via the crypto interfaces) and hand the plaintext XML here.
//
// Scope & layering notes:
//  • Protected string values are represented with `Protected="True"` and their
//    plaintext content. The KDBX inner-stream cipher (Salsa20/ChaCha20) that
//    obfuscates protected values *within* the encrypted block is applied by the
//    KDBX layer, not here — at this layer values are already in the clear.
//  • Times use ISO-8601 (KeePass 2.x text form), round-trippable losslessly.
//
// Uses the vetted `package:xml` parser/builder — no hand-rolled XML.

import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../model/attachment.dart';
import '../model/database.dart';
import '../model/entry.dart';
import '../model/field.dart';
import '../model/group.dart';
import '../model/protected_value.dart';

class KeePassXml {
  const KeePassXml();

  static const String _true = 'True';
  static const String _false = 'False';

  // ---------------------------------------------------------------- encode ---

  String encode(Database db, {bool pretty = true}) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="utf-8"');
    builder.element('KeePassFile', nest: () {
      builder.element('Meta', nest: () {
        _textEl(builder, 'Generator', db.meta.generator);
        _textEl(builder, 'DatabaseName', db.meta.name);
        if (db.meta.description != null) {
          _textEl(builder, 'DatabaseDescription', db.meta.description!);
        }
        _textEl(builder, 'RecycleBinEnabled',
            db.meta.recycleBinEnabled ? _true : _false,);
        if (db.meta.recycleBinUuid != null) {
          _textEl(builder, 'RecycleBinUUID', db.meta.recycleBinUuid!);
        }
        _textEl(builder, 'HistoryMaxItems', '${db.meta.historyMaxItems}');
        _textEl(builder, 'HistoryMaxSize', '${db.meta.historyMaxSize}');
        builder.element('Binaries', nest: () {
          for (final bin in db.binaryPool) {
            builder.element('Binary', nest: () {
              builder.attribute('ID', bin.id);
              if (bin.inlineData != null) {
                builder.text(base64.encode(bin.inlineData!));
              }
            },);
          }
        },);
        if (db.meta.customData.isNotEmpty) {
          builder.element('CustomData', nest: () {
            db.meta.customData.forEach((k, v) {
              builder.element('Item', nest: () {
                _textEl(builder, 'Key', k);
                _textEl(builder, 'Value', v);
              },);
            });
          },);
        }
      },);
      builder.element('Root', nest: () => _buildGroup(builder, db.root));
    },);
    // Pretty-printing must not corrupt value content: the xml pretty writer
    // normalizes (trims/collapses) whitespace inside text-only elements. KeePass
    // values can carry significant leading/trailing/internal whitespace, so
    // preserve whitespace verbatim for every leaf text element (Value, Name,
    // Notes, Key, …) while still indenting the structural elements.
    return builder.buildDocument().toXmlString(
          pretty: pretty,
          preserveWhitespace: (node) =>
              node is XmlElement &&
              node.children.isNotEmpty &&
              node.children.every((c) => c is XmlText),
        );
  }

  void _buildGroup(XmlBuilder builder, Group group) {
    builder.element('Group', nest: () {
      _textEl(builder, 'UUID', group.uuid);
      _textEl(builder, 'Name', group.name);
      if (group.notes != null) _textEl(builder, 'Notes', group.notes!);
      _textEl(builder, 'IconID', '${group.iconId}');
      if (group.customIconUuid != null) {
        _textEl(builder, 'CustomIconUUID', group.customIconUuid!);
      }
      for (final entry in group.entries) {
        _buildEntry(builder, entry);
      }
      for (final child in group.groups) {
        _buildGroup(builder, child);
      }
    },);
  }

  void _buildEntry(XmlBuilder builder, Entry entry, {bool asHistory = false}) {
    builder.element('Entry', nest: () {
      _textEl(builder, 'UUID', entry.uuid);
      _textEl(builder, 'IconID', '${entry.iconId}');
      if (entry.customIconUuid != null) {
        _textEl(builder, 'CustomIconUUID', entry.customIconUuid!);
      }
      if (entry.tags.isNotEmpty) {
        _textEl(builder, 'Tags', entry.tags.join(';'));
      }
      builder.element('Times', nest: () {
        if (entry.created != null) {
          _textEl(builder, 'CreationTime', entry.created!.toIso8601String());
        }
        if (entry.modified != null) {
          _textEl(builder, 'LastModificationTime',
              entry.modified!.toIso8601String(),);
        }
      },);
      for (final field in entry.fields.values) {
        builder.element('String', nest: () {
          _textEl(builder, 'Key', field.key);
          builder.element('Value', nest: () {
            if (field.isProtected) builder.attribute('Protected', _true);
            builder.text(field.value.reveal());
          },);
        },);
      }
      for (final att in entry.attachments) {
        builder.element('Binary', nest: () {
          _textEl(builder, 'Key', att.name);
          builder.element('Value', nest: () {
            builder.attribute('Ref', att.id);
          },);
        },);
      }
      // History versions are flat (no nested history) — guarded by asHistory.
      if (!asHistory && entry.history.isNotEmpty) {
        builder.element('History', nest: () {
          for (final h in entry.history) {
            _buildEntry(builder, h, asHistory: true);
          }
        },);
      }
    },);
  }

  void _textEl(XmlBuilder builder, String name, String value) {
    builder.element(name, nest: () => builder.text(value));
  }

  // ---------------------------------------------------------------- decode ---

  Database decode(String xml) {
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement; // KeePassFile
    final metaEl = root.getElement('Meta');
    final meta = _parseMeta(metaEl);
    final pool = _parseBinaries(metaEl);

    final rootEl = root.getElement('Root');
    final groupEl = rootEl?.getElement('Group');
    final rootGroup = groupEl != null
        ? _parseGroup(groupEl)
        : Group(uuid: 'root', name: 'Root');

    return Database(meta: meta, root: rootGroup, binaryPool: pool);
  }

  static bool _isZeroUuid(String b64) {
    try {
      return base64.decode(b64.trim()).every((b) => b == 0);
    } catch (_) {
      return false;
    }
  }

  DatabaseMeta _parseMeta(XmlElement? metaEl) {
    final customData = <String, String>{};
    final cd = metaEl?.getElement('CustomData');
    if (cd != null) {
      for (final item in cd.findElements('Item')) {
        final k = item.getElement('Key')?.innerText;
        final v = item.getElement('Value')?.innerText;
        if (k != null) customData[k] = v ?? '';
      }
    }
    final rbUuid = metaEl?.getElement('RecycleBinUUID')?.innerText;
    final hMaxItems = int.tryParse(
        metaEl?.getElement('HistoryMaxItems')?.innerText ?? '',);
    final hMaxSize = int.tryParse(
        metaEl?.getElement('HistoryMaxSize')?.innerText ?? '',);
    return DatabaseMeta(
      name: metaEl?.getElement('DatabaseName')?.innerText ?? 'Database',
      description: metaEl?.getElement('DatabaseDescription')?.innerText,
      generator: metaEl?.getElement('Generator')?.innerText ?? 'dgvault',
      recycleBinEnabled:
          metaEl?.getElement('RecycleBinEnabled')?.innerText != _false,
      // A zero UUID ("AAAA…==") means "no recycle bin assigned".
      recycleBinUuid: (rbUuid == null || rbUuid.isEmpty || _isZeroUuid(rbUuid))
          ? null
          : rbUuid,
      historyMaxItems: hMaxItems ?? 10,
      historyMaxSize: hMaxSize ?? 6 * 1024 * 1024,
      customData: customData,
    );
  }

  List<Attachment> _parseBinaries(XmlElement? metaEl) {
    final out = <Attachment>[];
    final binaries = metaEl?.getElement('Binaries');
    if (binaries == null) return out;
    for (final b in binaries.findElements('Binary')) {
      final id = b.getAttribute('ID');
      if (id == null) continue;
      Uint8List? data;
      final text = b.innerText.trim();
      if (text.isNotEmpty) data = base64.decode(text);
      out.add(Attachment(
        id: id,
        name: '',
        size: data?.length ?? 0,
        inlineData: data,
      ),);
    }
    return out;
  }

  Group _parseGroup(XmlElement el) {
    final group = Group(
      uuid: el.getElement('UUID')?.innerText ?? '',
      name: el.getElement('Name')?.innerText ?? '',
      notes: el.getElement('Notes')?.innerText,
      iconId: int.tryParse(el.getElement('IconID')?.innerText ?? '') ?? 48,
      customIconUuid: el.getElement('CustomIconUUID')?.innerText,
    );
    for (final entryEl in el.findElements('Entry')) {
      group.entries.add(_parseEntry(entryEl));
    }
    for (final childEl in el.findElements('Group')) {
      group.groups.add(_parseGroup(childEl));
    }
    return group;
  }

  Entry _parseEntry(XmlElement el) {
    final fields = <String, Field>{};
    for (final s in el.findElements('String')) {
      final key = s.getElement('Key')?.innerText;
      if (key == null) continue;
      final valueEl = s.getElement('Value');
      final protected = valueEl?.getAttribute('Protected') == _true;
      fields[key] = Field(
        key: key,
        value: InMemoryProtectedValue(
          valueEl?.innerText ?? '',
          isProtected: protected,
        ),
      );
    }

    final attachments = <Attachment>[];
    for (final b in el.findElements('Binary')) {
      final name = b.getElement('Key')?.innerText ?? '';
      final ref = b.getElement('Value')?.getAttribute('Ref');
      if (ref != null) {
        attachments.add(Attachment(id: ref, name: name, size: 0));
      }
    }

    final tagsText = el.getElement('Tags')?.innerText;
    final tags = (tagsText == null || tagsText.isEmpty)
        ? <String>[]
        : tagsText.split(RegExp(r'[;,]')).where((t) => t.isNotEmpty).toList();

    final times = el.getElement('Times');
    final history = <Entry>[];
    final historyEl = el.getElement('History');
    if (historyEl != null) {
      for (final h in historyEl.findElements('Entry')) {
        history.add(_parseEntry(h));
      }
    }

    return Entry(
      uuid: el.getElement('UUID')?.innerText ?? '',
      fields: fields,
      tags: tags,
      attachments: attachments,
      history: history,
      iconId: int.tryParse(el.getElement('IconID')?.innerText ?? '') ?? 0,
      customIconUuid: el.getElement('CustomIconUUID')?.innerText,
      created: _parseTime(times?.getElement('CreationTime')?.innerText),
      modified: _parseTime(times?.getElement('LastModificationTime')?.innerText),
    );
  }

  DateTime? _parseTime(String? text) {
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }
}
