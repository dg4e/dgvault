// dgvault — vault: responsive master/detail (two-pane wide, stacked narrow).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dgvault/core/core.dart';

import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/terminal_widgets.dart';
import 'entry_detail.dart';
import 'generator_sheet.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key, required this.controller});
  final VaultController controller;

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _search = TextEditingController();
  String _query = '';
  Entry? _selected;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSelect(Entry e, bool wide) {
    if (wide) {
      setState(() => _selected = e);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(
              backgroundColor: TermColors.surface,
              title: Text(e.title ?? 'entry',
                  style: mono(size: 15, color: TermColors.textBright),),
            ),
            body: EntryDetailView(entry: e),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final entries = widget.controller.search(_query);
    if (wide && _selected == null && entries.isNotEmpty) {
      _selected = entries.first;
    }
    if (_selected != null && !entries.contains(_selected)) {
      _selected = entries.isEmpty ? null : entries.first;
    }

    void gen() => showGenerator(context);
    final lock = widget.controller.lock;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): gen,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): gen,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lock,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): lock,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _Header(controller: widget.controller),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: 340,
                              child: _ListPane(
                                search: _search,
                                entries: entries,
                                selected: _selected,
                                onQuery: (q) => setState(() => _query = q),
                                onSelect: (e) => _onSelect(e, true),
                              ),
                            ),
                            const VerticalDivider(
                                width: 1, color: TermColors.border,),
                            Expanded(
                              child: _selected == null
                                  ? const _EmptyDetail()
                                  : EntryDetailView(entry: _selected!),
                            ),
                          ],
                        )
                      : _ListPane(
                          search: _search,
                          entries: entries,
                          selected: null,
                          onQuery: (q) => setState(() => _query = q),
                          onSelect: (e) => _onSelect(e, false),
                        ),
                ),
                StatusBar(
                  mode: 'UNLOCKED',
                  left: [
                    '${entries.length}/${widget.controller.entryCount} entries',
                    if (_query.isNotEmpty) 'filter:"$_query"',
                  ],
                  right: const ['aes-256', '^G gen', '^L lock'],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final VaultController controller;
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
          Text('dgvault',
              style: mono(
                  size: 15, color: TermColors.green, weight: FontWeight.w700,),),
          Text(' ://vault', style: mono(size: 13, color: TermColors.textDim)),
          const Spacer(),
          _HeaderBtn(
              label: 'gen',
              icon: Icons.casino_outlined,
              onTap: () => showGenerator(context),),
          const SizedBox(width: 6),
          _HeaderBtn(
              label: 'lock',
              icon: Icons.lock_outline,
              color: TermColors.amber,
              onTap: controller.lock,),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.color = TermColors.green,});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.5)),),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: mono(size: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ListPane extends StatelessWidget {
  const _ListPane({
    required this.search,
    required this.entries,
    required this.selected,
    required this.onQuery,
    required this.onSelect,
  });

  final TextEditingController search;
  final List<Entry> entries;
  final Entry? selected;
  final ValueChanged<String> onQuery;
  final ValueChanged<Entry> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: PromptField(
            controller: search,
            sigil: '/',
            sigilColor: TermColors.cyan,
            hint: 'search all fields…',
            onChanged: onQuery,
            onSubmitted: onQuery,
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text('no matches',
                      style: mono(color: TermColors.textFaint),),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, i) => _EntryRow(
                    entry: entries[i],
                    selected: entries[i] == selected,
                    onTap: () => onSelect(entries[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(
      {required this.entry, required this.selected, required this.onTap,});
  final Entry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final user = entry.fields[Field.userName]?.value.reveal() ?? '';
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? TermColors.surfaceAlt : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: selected ? TermColors.green : Colors.transparent,
              width: 2,
            ),
            bottom: const BorderSide(color: TermColors.border, width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text(
              selected ? '▸ ' : '  ',
              style: mono(size: 13, color: TermColors.green),
            ),
            const Icon(Icons.vpn_key_outlined,
                size: 14, color: TermColors.greenDim,),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title ?? '(untitled)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 14, color: TermColors.textBright),
                  ),
                  if (user.isNotEmpty)
                    Text(
                      user,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 11, color: TermColors.textDim),
                    ),
                ],
              ),
            ),
            if (entry.tags.isNotEmpty)
              Text(
                '#${entry.tags.first}',
                style: mono(size: 10, color: TermColors.magenta),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();
  @override
  Widget build(BuildContext context) => Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('select an entry', style: mono(color: TermColors.textFaint)),
            const SizedBox(width: 6),
            const BlinkingCursor(color: TermColors.textFaint),
          ],
        ),
      );
}
