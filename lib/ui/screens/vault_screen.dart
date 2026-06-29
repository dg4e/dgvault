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
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _onSearchKey);
  String _query = '';
  Entry? _selected;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Entry> get _entries => widget.controller.search(_query);

  // Arrow keys navigate the list even while the search box is focused (fzf-style).
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    final list = _entries;
    if (list.isEmpty) return;
    final i = _selected == null ? -1 : list.indexOf(_selected!);
    final next = (i + delta).clamp(0, list.length - 1);
    setState(() => _selected = list[next]);
  }

  void _focusSearch() => _searchFocus.requestFocus();

  // Esc: clear an active search first; otherwise lock the vault. Focus stays on
  // the search field so a second Esc is still caught (and locks).
  void _onEscape() {
    if (_search.text.isNotEmpty || _query.isNotEmpty) {
      _search.clear();
      setState(() => _query = '');
    } else {
      widget.controller.lock();
    }
  }

  void _copyPassword() {
    final pw = _selected?.fields[Field.password]?.value.reveal();
    if (pw == null || pw.isEmpty) return;
    copyWithFlash(context, pw, 'password');
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
              title: Text(
                e.title ?? 'entry',
                style: mono(size: 15, color: TermColors.textBright),
              ),
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
      // Bind both Control and Meta (⌘) so the shortcuts feel native on every OS.
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): gen,
        const SingleActivator(LogicalKeyboardKey.keyG, meta: true): gen,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true): lock,
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true): lock,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _copyPassword,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _copyPassword,
        const SingleActivator(LogicalKeyboardKey.slash): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
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
                                searchFocus: _searchFocus,
                                entries: entries,
                                selected: _selected,
                                onQuery: (q) => setState(() => _query = q),
                                onSelect: (e) => _onSelect(e, true),
                              ),
                            ),
                            const VerticalDivider(
                              width: 1,
                              color: TermColors.border,
                            ),
                            Expanded(
                              child: _selected == null
                                  ? const _EmptyDetail()
                                  : EntryDetailView(entry: _selected!),
                            ),
                          ],
                        )
                      : _ListPane(
                          search: _search,
                          searchFocus: _searchFocus,
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
                  right: [
                    '/ find',
                    '↑↓ nav',
                    '${hotkey('C')} copy',
                    '${hotkey('G')} gen',
                    '${hotkey('L')} lock',
                    'esc',
                  ],
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
          Text(
            'dgvault',
            style: mono(
              size: 15,
              color: TermColors.green,
              weight: FontWeight.w700,
            ),
          ),
          Text(' ://vault', style: mono(size: 13, color: TermColors.textDim)),
          const Spacer(),
          _HeaderBtn(
            label: 'gen',
            icon: Icons.casino_outlined,
            onTap: () => showGenerator(context),
          ),
          const SizedBox(width: 6),
          _HeaderBtn(
            label: 'lock',
            icon: Icons.lock_outline,
            color: TermColors.amber,
            onTap: controller.lock,
          ),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = TermColors.green,
  });
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
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
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
    required this.searchFocus,
    required this.entries,
    required this.selected,
    required this.onQuery,
    required this.onSelect,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
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
            focusNode: searchFocus,
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
                  child: Text(
                    'no matches',
                    style: mono(color: TermColors.textFaint),
                  ),
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
  const _EntryRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });
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
            const Icon(
              Icons.vpn_key_outlined,
              size: 14,
              color: TermColors.greenDim,
            ),
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
