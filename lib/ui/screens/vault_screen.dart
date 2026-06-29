// dgvault — vault: responsive master/detail (two-pane wide, stacked narrow).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dgvault/core/core.dart';

import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/folder_tree.dart';
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
  Group? _group; // selected folder; null → root view (minus recycle bin)

  @override
  void initState() {
    super.initState();
    // Let the app-level menu (single PlatformMenuBar) drive these while mounted.
    widget.controller.onGenerate = () => showGenerator(context);
    widget.controller.onCopyPassword = _copyPassword;
  }

  @override
  void dispose() {
    widget.controller.onGenerate = null;
    widget.controller.onCopyPassword = null;
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Entries to show: search results (across the whole vault) when searching,
  /// otherwise the selected folder's entries. The root view excludes the
  /// Recycle Bin so trashed/old entries don't masquerade as duplicates.
  List<Entry> get _entries {
    if (_query.isNotEmpty) return widget.controller.search(_query);
    final root = widget.controller.rootGroup;
    if (root == null) return const [];
    final group = _group ?? root;
    if (identical(group, root)) {
      final rb = widget.controller.recycleBinUuid;
      return root.entriesExcluding(rb == null ? const {} : {rb}).toList();
    }
    return group.allEntries.toList();
  }

  void _selectGroup(Group g) => setState(() {
        _group = g;
        _selected = null;
      });

  void _pickFolder() {
    final root = widget.controller.rootGroup;
    if (root == null) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: TermColors.bg,
      builder: (_) => SizedBox(
        height: 360,
        child: FolderTree(
          root: root,
          selected: _group ?? root,
          recycleBinUuid: widget.controller.recycleBinUuid,
          onSelect: (g) {
            Navigator.pop(context);
            _selectGroup(g);
          },
        ),
      ),
    );
  }

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
    final root = widget.controller.rootGroup;
    final entries = _entries;
    final folderName =
        (_group == null || (root != null && identical(_group, root)))
            ? 'All'
            : (_group?.name ?? 'All');
    if (wide && _selected == null && entries.isNotEmpty) {
      _selected = entries.first;
    }
    if (_selected != null && !entries.contains(_selected)) {
      _selected = entries.isEmpty ? null : entries.first;
    }

    void gen() => showGenerator(context);
    final lock = widget.controller.lock;
    final Widget tree = CallbackShortcuts(
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
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            widget.controller.save,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            widget.controller.save,
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
                            if (root != null) ...[
                              SizedBox(
                                width: 180,
                                child: FolderTree(
                                  root: root,
                                  selected: _group ?? root,
                                  recycleBinUuid:
                                      widget.controller.recycleBinUuid,
                                  onSelect: _selectGroup,
                                ),
                              ),
                              const VerticalDivider(
                                  width: 1, color: TermColors.border,),
                            ],
                            SizedBox(
                              width: 320,
                              child: _ListPane(
                                search: _search,
                                searchFocus: _searchFocus,
                                entries: entries,
                                selected: _selected,
                                folderName: folderName,
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
                          folderName: folderName,
                          onFolderTap: _pickFolder,
                          onQuery: (q) => setState(() => _query = q),
                          onSelect: (e) => _onSelect(e, false),
                        ),
                ),
                StatusBar(
                  mode: 'UNLOCKED',
                  left: [
                    if (_query.isEmpty) '⌂ $folderName',
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

    // The macOS ⌘ commands live in the single app-level PlatformMenuBar (see
    // app_menu.dart), driven via controller hooks registered in initState.
    return tree;
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
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '· ${controller.fileName ?? '(in memory)'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(size: 13, color: TermColors.textDim),
            ),
          ),
          if (controller.status == VaultStatus.saving) ...[
            const SizedBox(width: 8),
            Text('saving…', style: mono(size: 11, color: TermColors.amber)),
          ],
          const Spacer(),
          _HeaderBtn(
            label: 'save',
            icon: Icons.save_outlined,
            tooltip: 'Save to file (${hotkey('S')})',
            onTap: controller.save,
          ),
          const SizedBox(width: 6),
          _HeaderBtn(
            label: 'gen',
            icon: Icons.casino_outlined,
            tooltip: 'Generate a password (${hotkey('G')})',
            onTap: () => showGenerator(context),
          ),
          const SizedBox(width: 6),
          _HeaderBtn(
            label: 'lock',
            icon: Icons.lock_outline,
            color: TermColors.amber,
            tooltip: 'Lock the vault (${hotkey('L')})',
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
    this.tooltip,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? label,
      child: InkWell(
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
    required this.folderName,
    this.onFolderTap,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final List<Entry> entries;
  final Entry? selected;
  final String folderName;
  final VoidCallback? onFolderTap; // non-null on narrow → opens the folder picker
  final ValueChanged<String> onQuery;
  final ValueChanged<Entry> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Folder breadcrumb — tappable on narrow to switch folders.
        InkWell(
          onTap: onFolderTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.folder_open_outlined,
                    size: 13, color: TermColors.textDim,),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(folderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 12, color: TermColors.cyan),),
                ),
                if (onFolderTap != null)
                  const Icon(Icons.expand_more,
                      size: 14, color: TermColors.textDim,),
              ],
            ),
          ),
        ),
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
    final url = entry.fields[Field.url]?.value.reveal();
    final tip = [
      'open ${entry.title ?? '(untitled)'}',
      if (user.isNotEmpty) 'user: $user',
      if (url != null && url.isNotEmpty) url,
    ].join('\n');
    return Tooltip(
      message: tip,
      child: InkWell(
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
