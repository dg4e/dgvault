// dgvault — entry detail: fields with reveal + copy, terminal styled.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../theme/terminal_theme.dart';
import '../widgets/terminal_widgets.dart';

class EntryDetailView extends StatefulWidget {
  const EntryDetailView({super.key, required this.entry});
  final Entry entry;

  @override
  State<EntryDetailView> createState() => _EntryDetailViewState();
}

class _EntryDetailViewState extends State<EntryDetailView> {
  final Set<String> _revealed = {};

  @override
  void didUpdateWidget(EntryDetailView old) {
    super.didUpdateWidget(old);
    if (old.entry.uuid != widget.entry.uuid) _revealed.clear();
  }

  static const _order = [
    Field.userName,
    Field.url,
    Field.password,
    'TOTP',
    Field.notes,
  ];

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final title = e.title ?? '(untitled)';
    final keys = <String>[
      ..._order.where(e.fields.containsKey),
      ...e.fields.keys.where((k) => k != Field.title && !_order.contains(k)),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Text('▌', style: mono(size: 22, color: TermColors.green)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: mono(
                  size: 20,
                  color: TermColors.textBright,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (e.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in e.tags) TagChip(t)],
          ),
        ],
        const SizedBox(height: 20),
        for (final k in keys)
          _FieldRow(
            label: _labelFor(k),
            value: e.fields[k]!.value.reveal(),
            secret: e.fields[k]!.isProtected,
            revealed: _revealed.contains(k),
            onToggle: () => setState(
              () => _revealed.contains(k)
                  ? _revealed.remove(k)
                  : _revealed.add(k),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          'uuid: ${e.uuid}   modified: ${e.modified?.toIso8601String() ?? "—"}',
          style: mono(size: 11, color: TermColors.textFaint),
        ),
      ],
    );
  }

  String _labelFor(String k) {
    switch (k) {
      case Field.userName:
        return 'username';
      case Field.password:
        return 'password';
      case Field.url:
        return 'url';
      case Field.notes:
        return 'notes';
      default:
        return k.toLowerCase();
    }
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.secret,
    required this.revealed,
    required this.onToggle,
  });

  final String label;
  final String value;
  final bool secret;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final masked = secret && !revealed;
    final shown = masked ? '•' * value.length.clamp(8, 24) : value;
    final isNotes = label == 'notes';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(label),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: TermColors.surfaceAlt,
                    border: Border(
                      left: BorderSide(
                        color: TermColors.borderBright,
                        width: 2,
                      ),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Text(
                    shown,
                    maxLines: isNotes ? null : 1,
                    overflow: isNotes ? null : TextOverflow.ellipsis,
                    style: mono(
                      size: 14,
                      color: secret && !revealed
                          ? TermColors.textDim
                          : TermColors.textBright,
                    ),
                  ),
                ),
              ),
              if (secret)
                _IconBtn(
                  icon: revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  tooltip: revealed ? 'Hide $label' : 'Reveal $label',
                  onTap: onToggle,
                ),
              _IconBtn(
                icon: Icons.content_copy_outlined,
                tooltip: 'Copy $label',
                onTap: () => copyWithFlash(context, value, label),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: TermColors.textDim),
        ),
      ),
    );
  }
}
