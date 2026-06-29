// dgvault — vault: responsive master/detail (two-pane wide, stacked narrow).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dgvault/core/core.dart';

import '../state/sorting.dart';
import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/folder_tree.dart';
import '../widgets/terminal_widgets.dart';
import 'entry_detail.dart';
import 'entry_editor.dart';
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
  EntrySort _entrySort = EntrySort.manual;
  FolderSort _folderSort = FolderSort.manual;

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
    if (_query.isNotEmpty) return _entrySort.apply(widget.controller.search(_query));
    final root = widget.controller.rootGroup;
    if (root == null) return const [];
    final group = _group ?? root;
    final raw = identical(group, root)
        ? root
            .entriesExcluding(
                widget.controller.recycleBinUuid == null
                    ? const {}
                    : {widget.controller.recycleBinUuid!},)
            .toList()
        : group.allEntries.toList();
    return _entrySort.apply(raw);
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
        height: 420,
        child: FolderTree(
          root: root,
          selected: _group ?? root,
          recycleBinUuid: widget.controller.recycleBinUuid,
          sort: _folderSort,
          onSortChanged: (s) => setState(() => _folderSort = s),
          onAddFolder: (parent) {
            Navigator.pop(context);
            _addFolder(parent);
          },
          onRenameFolder: (g) {
            Navigator.pop(context);
            _renameFolder(g);
          },
          onDeleteFolder: (g) {
            Navigator.pop(context);
            _deleteFolder(g);
          },
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
            body: EntryDetailView(
              entry: e,
              onEdit: () => _editEntry(e),
              onDelete: () => _deleteEntry(e, pop: true),
              onRestore: (i) => _restoreHistory(e, i),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _addEntry() async {
    // Drop into the selected folder; root/null lets the controller choose.
    final root = widget.controller.rootGroup;
    final group =
        (_group == null || (root != null && identical(_group, root)))
            ? null
            : _group;
    await openEntryEditor(context, widget.controller, group: group);
    if (mounted) setState(() {});
  }

  Future<void> _editEntry(Entry e) async {
    await openEntryEditor(context, widget.controller, entry: e);
    if (mounted) setState(() {});
  }

  void _restoreHistory(Entry e, int index) {
    widget.controller.restoreHistory(e, index);
    setState(() {});
  }

  Future<void> _deleteEntry(Entry e, {bool pop = false}) async {
    final binned = widget.controller.recycleBinEnabled;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TermColors.surface,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: TermColors.border),
          borderRadius: BorderRadius.zero,
        ),
        title: Text('// DELETE ENTRY',
            style: mono(size: 13, color: TermColors.red, letterSpacing: 1.5),),
        content: Text(
          binned
              ? 'Move "${e.title ?? '(untitled)'}" to the Recycle Bin?'
              : 'Permanently delete "${e.title ?? '(untitled)'}"? '
                  'This cannot be undone.',
          style: mono(size: 13, color: TermColors.text),
        ),
        actions: [
          TermButton(
            label: 'CANCEL',
            color: TermColors.textDim,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(width: 8),
          TermButton(
            label: binned ? 'MOVE TO TRASH' : 'DELETE',
            color: TermColors.red,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.controller.deleteEntry(e);
    if (pop && mounted) Navigator.of(context).pop(); // close narrow detail route
    if (mounted) {
      setState(() {
        if (identical(_selected, e)) _selected = null;
      });
    }
  }

  // ---- folder operations --------------------------------------------------

  Future<void> _addFolder(Group parent) async {
    final name = await _promptName(
        title: 'NEW FOLDER',
        hint: 'folder name',
        label: 'CREATE',);
    if (name == null || name.isEmpty) return;
    final g = widget.controller.addGroup(name, parent: parent);
    if (mounted) setState(() => _selectGroup(g));
  }

  Future<void> _renameFolder(Group g) async {
    final name = await _promptName(
        title: 'RENAME FOLDER',
        hint: 'folder name',
        label: 'RENAME',
        initial: g.name,);
    if (name == null || name.isEmpty) return;
    widget.controller.renameGroup(g, name);
    if (mounted) setState(() {});
  }

  Future<void> _deleteFolder(Group g) async {
    final binned = widget.controller.recycleBinEnabled &&
        g.uuid != widget.controller.recycleBinUuid;
    final n = g.allEntries.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TermColors.surface,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: TermColors.border),
          borderRadius: BorderRadius.zero,
        ),
        title: Text('// DELETE FOLDER',
            style: mono(size: 13, color: TermColors.red, letterSpacing: 1.5),),
        content: Text(
          binned
              ? 'Move "${g.name}" and its $n entr${n == 1 ? "y" : "ies"} '
                  'to the Recycle Bin?'
              : 'Permanently delete "${g.name}" and its $n '
                  'entr${n == 1 ? "y" : "ies"}? This cannot be undone.',
          style: mono(size: 13, color: TermColors.text),
        ),
        actions: [
          TermButton(
            label: 'CANCEL',
            color: TermColors.textDim,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          const SizedBox(width: 8),
          TermButton(
            label: binned ? 'MOVE TO TRASH' : 'DELETE',
            color: TermColors.red,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.controller.deleteGroup(g);
    if (mounted) {
      setState(() {
        if (identical(_group, g)) _group = null; // back to All
        _selected = null;
      });
    }
  }

  /// A single-line text prompt dialog (folder name). Returns the trimmed text,
  /// or null if cancelled.
  Future<String?> _promptName({
    required String title,
    required String hint,
    required String label,
    String initial = '',
  }) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: TermColors.surface,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: TermColors.border),
          borderRadius: BorderRadius.zero,
        ),
        title: Text('// $title',
            style:
                mono(size: 13, color: TermColors.green, letterSpacing: 1.5),),
        content: PromptField(
          controller: ctl,
          sigil: '›',
          hint: hint,
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, ctl.text.trim()),
        ),
        actions: [
          TermButton(
            label: 'CANCEL',
            color: TermColors.textDim,
            onPressed: () => Navigator.pop(ctx),
          ),
          const SizedBox(width: 8),
          TermButton(
            label: label,
            onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          ),
        ],
      ),
    );
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
                                width: 200,
                                child: FolderTree(
                                  root: root,
                                  selected: _group ?? root,
                                  recycleBinUuid:
                                      widget.controller.recycleBinUuid,
                                  onSelect: _selectGroup,
                                  sort: _folderSort,
                                  onSortChanged: (s) =>
                                      setState(() => _folderSort = s),
                                  onAddFolder: _addFolder,
                                  onRenameFolder: _renameFolder,
                                  onDeleteFolder: _deleteFolder,
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
                                sort: _entrySort,
                                onSortChanged: (s) =>
                                    setState(() => _entrySort = s),
                                onAdd: _addEntry,
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
                                  : EntryDetailView(
                                      entry: _selected!,
                                      onEdit: () => _editEntry(_selected!),
                                      onDelete: () => _deleteEntry(_selected!),
                                      onRestore: (i) =>
                                          _restoreHistory(_selected!, i),
                                    ),
                            ),
                          ],
                        )
                      : _ListPane(
                          search: _search,
                          searchFocus: _searchFocus,
                          entries: entries,
                          selected: null,
                          folderName: folderName,
                          sort: _entrySort,
                          onSortChanged: (s) =>
                              setState(() => _entrySort = s),
                          onFolderTap: _pickFolder,
                          onAdd: _addEntry,
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
            label: 'opts',
            icon: Icons.settings_outlined,
            color: TermColors.cyan,
            tooltip: 'Vault settings',
            onTap: () => _showSettings(context, controller),
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

/// Vault settings sheet: recycle bin, key-derivation rounds + benchmark, and
/// entry-history limits.
void _showSettings(BuildContext context, VaultController controller) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: TermColors.bg,
    isScrollControlled: true,
    builder: (_) => _SettingsSheet(controller: controller),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller});
  final VaultController controller;
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final _rounds =
      TextEditingController(text: '${widget.controller.kdfIterations}');
  late final _histItems =
      TextEditingController(text: '${widget.controller.historyMaxItems}');
  late final _histSize = TextEditingController(
      text: '${(widget.controller.historyMaxSize / (1024 * 1024)).round()}',);
  bool _benchmarking = false;

  @override
  void dispose() {
    _rounds.dispose();
    _histItems.dispose();
    _histSize.dispose();
    super.dispose();
  }

  void _commitRounds() {
    final v = int.tryParse(_rounds.text.trim());
    if (v != null && v >= 1) widget.controller.setKdfIterations(v);
  }

  void _commitHistItems() {
    final v = int.tryParse(_histItems.text.trim());
    if (v != null) widget.controller.setHistoryMaxItems(v);
  }

  void _commitHistSize() {
    final mib = int.tryParse(_histSize.text.trim());
    if (mib != null) widget.controller.setHistoryMaxSize(mib * 1024 * 1024);
  }

  Future<void> _benchmark() async {
    setState(() => _benchmarking = true);
    final iters = await widget.controller.benchmarkKdfIterations();
    if (!mounted) return;
    widget.controller.setKdfIterations(iters);
    setState(() {
      _rounds.text = '$iters';
      _benchmarking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final roundsLabel =
        c.kdfIsArgon2 ? 'iterations (argon2 passes)' : 'transform rounds';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(child: SectionLabel('vault settings')),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child:
                          Icon(Icons.close, size: 18, color: TermColors.textDim),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Recycle bin
              Row(
                children: [
                  Expanded(
                    child: _settingText(
                      'Recycle Bin',
                      'Deleted items move to the trash instead of being '
                          'permanently erased.',
                    ),
                  ),
                  Switch(
                    value: c.recycleBinEnabled,
                    activeThumbColor: TermColors.green,
                    onChanged: (v) {
                      c.setRecycleBinEnabled(v);
                      setState(() {});
                    },
                  ),
                ],
              ),
              const _SettingsDivider(),

              // Key derivation
              const SectionLabel('key derivation'),
              const SizedBox(height: 6),
              Text(
                'Higher $roundsLabel slow down brute-force guessing but make '
                'unlocking take longer. Benchmark targets ~1s on this machine.',
                style: mono(size: 11, color: TermColors.textDim),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionLabel(roundsLabel),
                        PromptField(
                          controller: _rounds,
                          sigil: '#',
                          onChanged: (_) => _commitRounds(),
                          onSubmitted: (_) => _commitRounds(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  TermButton(
                    label: 'BENCHMARK',
                    tooltip: 'Find the rounds that take ~1 second here',
                    busy: _benchmarking,
                    onPressed: _benchmarking ? null : _benchmark,
                  ),
                ],
              ),
              const _SettingsDivider(),

              // History
              const SectionLabel('entry history'),
              const SizedBox(height: 6),
              Text(
                'Limits on retained prior versions per entry. Use -1 for '
                'unlimited.',
                style: mono(size: 11, color: TermColors.textDim),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('max items'),
                        PromptField(
                          controller: _histItems,
                          sigil: '#',
                          onChanged: (_) => _commitHistItems(),
                          onSubmitted: (_) => _commitHistItems(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionLabel('max size (MiB)'),
                        PromptField(
                          controller: _histSize,
                          sigil: '#',
                          onChanged: (_) => _commitHistSize(),
                          onSubmitted: (_) => _commitHistSize(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Changes are saved with the vault (⌘S).',
                style: mono(size: 11, color: TermColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingText(String title, String desc) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: mono(size: 14, color: TermColors.textBright)),
          const SizedBox(height: 2),
          Text(desc, style: mono(size: 11, color: TermColors.textDim)),
        ],
      );
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(height: 1, color: TermColors.border),
      );
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
    required this.sort,
    required this.onSortChanged,
    this.onFolderTap,
    this.onAdd,
  });

  final TextEditingController search;
  final FocusNode searchFocus;
  final List<Entry> entries;
  final Entry? selected;
  final String folderName;
  final EntrySort sort;
  final ValueChanged<EntrySort> onSortChanged;
  final VoidCallback? onFolderTap; // non-null on narrow → opens the folder picker
  final VoidCallback? onAdd; // create a new entry in this folder
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
                Tooltip(
                  message: 'Sort entries (${sort.label})',
                  child: PopupMenuButton<EntrySort>(
                    icon: const Icon(Icons.sort,
                        size: 16, color: TermColors.textDim,),
                    tooltip: '',
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    constraints: const BoxConstraints(),
                    color: TermColors.surfaceAlt,
                    onSelected: onSortChanged,
                    itemBuilder: (_) => [
                      for (final s in EntrySort.values)
                        PopupMenuItem<EntrySort>(
                          value: s,
                          child: Text(
                            '${s == sort ? "› " : "  "}${s.label}',
                            style: mono(
                                size: 12,
                                color: s == sort
                                    ? TermColors.green
                                    : TermColors.text,),
                          ),
                        ),
                    ],
                  ),
                ),
                if (onAdd != null)
                  Tooltip(
                    message: 'New entry',
                    child: InkWell(
                      onTap: onAdd,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.add,
                            size: 18, color: TermColors.green,),
                      ),
                    ),
                  ),
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
