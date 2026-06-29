// dgvault — entry detail: fields with reveal + copy, terminal styled.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../theme/terminal_theme.dart';
import '../widgets/terminal_widgets.dart';

class EntryDetailView extends StatefulWidget {
  const EntryDetailView({
    super.key,
    required this.entry,
    this.onEdit,
    this.onDelete,
    this.onRestore,
  });
  final Entry entry;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<int>? onRestore; // restore history[index]

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
            if (widget.onEdit != null)
              _ActionBtn(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit entry',
                  onTap: widget.onEdit!,),
            if (widget.onDelete != null)
              _ActionBtn(
                  icon: Icons.delete_outline,
                  tooltip: 'Delete entry',
                  color: TermColors.red,
                  onTap: widget.onDelete!,),
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
        if (e.history.isNotEmpty) ...[
          const SizedBox(height: 24),
          _HistorySection(history: e.history, onRestore: widget.onRestore),
        ],
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

/// A small bordered action button (EDIT / DELETE) shown beside the title.
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = TermColors.textDim,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: color)),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

/// History viewer: prior versions of an entry (most recent first), each
/// expandable to inspect its fields, with a Restore action.
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history, this.onRestore});
  final List<Entry> history;
  final ValueChanged<int>? onRestore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('history (${history.length})'),
        for (var i = history.length - 1; i >= 0; i--)
          _HistoryRow(
            version: history[i],
            label: 'v$i',
            onRestore: onRestore == null ? null : () => onRestore!(i),
          ),
      ],
    );
  }
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required this.version,
    required this.label,
    this.onRestore,
  });
  final Entry version;
  final String label;
  final VoidCallback? onRestore;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.version;
    final when = v.modified?.toIso8601String() ?? '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(border: Border.all(color: TermColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Text(_open ? '▾' : '▸',
                      style: mono(size: 13, color: TermColors.green),),
                  const SizedBox(width: 8),
                  Text(widget.label,
                      style: mono(
                          size: 12,
                          color: TermColors.text,
                          weight: FontWeight.w700,),),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(v.title ?? '(untitled)',
                        overflow: TextOverflow.ellipsis,
                        style: mono(size: 12, color: TermColors.textDim),),
                  ),
                  Text(when,
                      style: mono(size: 10, color: TermColors.textFaint),),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const Divider(height: 1, color: TermColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in v.fields.entries)
                    if (e.key != Field.title)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '${e.key}: ${e.value.isProtected ? "••••••••" : e.value.value.reveal()}',
                          style: mono(size: 12, color: TermColors.text),
                        ),
                      ),
                  if (widget.onRestore != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TermButton(
                        label: 'RESTORE',
                        tooltip: 'Restore this version',
                        onPressed: widget.onRestore,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
