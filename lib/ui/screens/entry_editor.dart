// dgvault — entry editor (create / edit), terminal styled.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../anim/fx.dart';
import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/terminal_widgets.dart';
import 'generator_sheet.dart';

/// Push the editor. [entry] null → create a new entry in [group].
Future<void> openEntryEditor(
  BuildContext context,
  VaultController controller, {
  Entry? entry,
  Group? group,
}) {
  return Navigator.of(context).push(
    fxRoute(EntryEditor(controller: controller, entry: entry, group: group)),
  );
}

class EntryEditor extends StatefulWidget {
  const EntryEditor({super.key, required this.controller, this.entry, this.group});
  final VaultController controller;
  final Entry? entry;
  final Group? group;

  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> {
  late final _title = _ctl(Field.title);
  late final _user = _ctl(Field.userName);
  late final _password = _ctl(Field.password);
  late final _url = _ctl(Field.url);
  late final _totp = _ctl('TOTP');
  late final _notes = _ctl(Field.notes);
  late final _tags =
      TextEditingController(text: widget.entry?.tags.join(', ') ?? '');
  bool _revealPw = false;

  bool get _isNew => widget.entry == null;

  TextEditingController _ctl(String key) =>
      TextEditingController(text: widget.entry?.fields[key]?.value.reveal() ?? '');

  @override
  void dispose() {
    for (final c in [_title, _user, _password, _url, _totp, _notes, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    final c = widget.controller;
    if (_isNew) {
      final e = Entry(
        uuid: c.newUuid(),
        fields: _buildFields(),
        tags: _parseTags(),
        created: DateTime.now().toUtc(),
        modified: DateTime.now().toUtc(),
      );
      c.addEntry(e, group: widget.group);
    } else {
      c.updateEntry(widget.entry!, (d) {
        d.fields
          ..clear()
          ..addAll(_buildFields());
        d.tags
          ..clear()
          ..addAll(_parseTags());
      });
    }
    Navigator.of(context).pop();
  }

  Map<String, Field> _buildFields() {
    Field plain(String k, String v) =>
        Field(key: k, value: InMemoryProtectedValue.plain(v));
    Field secret(String k, String v) =>
        Field(key: k, value: InMemoryProtectedValue(v));
    return {
      Field.title: plain(Field.title, _title.text),
      if (_user.text.isNotEmpty) Field.userName: plain(Field.userName, _user.text),
      if (_password.text.isNotEmpty)
        Field.password: secret(Field.password, _password.text),
      if (_url.text.isNotEmpty) Field.url: plain(Field.url, _url.text),
      if (_totp.text.isNotEmpty) 'TOTP': secret('TOTP', _totp.text),
      if (_notes.text.isNotEmpty) Field.notes: plain(Field.notes, _notes.text),
    };
  }

  List<String> _parseTags() => _tags.text
      .split(RegExp('[;,]'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EditorHeader(
              title: _isNew ? 'new entry' : 'edit entry',
              onCancel: () => Navigator.of(context).pop(),
              onSave: _save,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _field('title', _title, autofocus: true),
                  _field('username', _user),
                  _passwordField(),
                  _field('url', _url),
                  _field('totp (otpauth:// or base32)', _totp),
                  _field('notes', _notes, maxLines: 5),
                  _field('tags (comma-separated)', _tags),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
      {int maxLines = 1, bool autofocus = false,}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          PromptField(
            controller: c,
            sigil: '›',
            autofocus: autofocus,
            maxLines: maxLines,
          ),
        ],
      ),
    );
  }

  Widget _passwordField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('password'),
          Row(
            children: [
              Expanded(
                child: PromptField(
                  controller: _password,
                  sigil: '›',
                  obscure: !_revealPw,
                ),
              ),
              Tooltip(
                message: _revealPw ? 'Hide' : 'Reveal',
                child: IconButton(
                  icon: Icon(
                      _revealPw
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: TermColors.textDim,),
                  onPressed: () => setState(() => _revealPw = !_revealPw),
                ),
              ),
              const SizedBox(width: 4),
              TermButton(
                label: 'GEN',
                tooltip: 'Generate a password',
                onPressed: () => showGenerator(context,
                    onUse: (pw) => setState(() => _password.text = pw),),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader(
      {required this.title, required this.onCancel, required this.onSave,});
  final String title;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: TermColors.surface,
        border: Border(bottom: BorderSide(color: TermColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Text('┤ $title ├',
              style:
                  mono(size: 14, color: TermColors.green, weight: FontWeight.w600),),
          const Spacer(),
          TermButton(label: 'CANCEL', color: TermColors.textDim, onPressed: onCancel),
          const SizedBox(width: 10),
          TermButton(label: 'SAVE', onPressed: onSave),
        ],
      ),
    );
  }
}
