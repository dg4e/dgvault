// dgvault — folder (group) tree sidebar with add/rename/delete + sort.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../state/sorting.dart';
import '../theme/terminal_theme.dart';

class FolderTree extends StatelessWidget {
  const FolderTree({
    super.key,
    required this.root,
    required this.selected,
    required this.onSelect,
    this.recycleBinUuid,
    this.sort = FolderSort.manual,
    this.onSortChanged,
    this.onAddFolder,
    this.onRenameFolder,
    this.onDeleteFolder,
  });

  final Group root;
  final Group selected;
  final ValueChanged<Group> onSelect;
  final String? recycleBinUuid;

  final FolderSort sort;
  final ValueChanged<FolderSort>? onSortChanged;

  /// Folder mutations — when null the tree is read-only (e.g. a picker sheet).
  final ValueChanged<Group>? onAddFolder; // add a subfolder under the group
  final ValueChanged<Group>? onRenameFolder;
  final ValueChanged<Group>? onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void walk(Group g, int depth) {
      rows.add(_FolderRow(
        group: g,
        depth: depth,
        selected: identical(g, selected) || g.uuid == selected.uuid,
        isTrash: g.uuid == recycleBinUuid,
        isRoot: identical(g, root),
        onTap: () => onSelect(g),
        onAddFolder: onAddFolder,
        onRenameFolder: onRenameFolder,
        onDeleteFolder: onDeleteFolder,
      ),);
      for (final child in sort.apply(g.groups)) {
        walk(child, depth + 1);
      }
    }

    walk(root, 0);

    return Container(
      color: TermColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Row(
              children: [
                Flexible(
                  child: Text('// FOLDERS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                          size: 11,
                          color: TermColors.textDim,
                          letterSpacing: 1.5,),),
                ),
                const Spacer(),
                if (onSortChanged != null)
                  Tooltip(
                    message: 'Sort folders (${sort.label})',
                    child: PopupMenuButton<FolderSort>(
                      icon: const Icon(Icons.sort,
                          size: 16, color: TermColors.textDim,),
                      tooltip: '',
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                      color: TermColors.surfaceAlt,
                      onSelected: onSortChanged,
                      itemBuilder: (_) => [
                        for (final s in FolderSort.values)
                          _sortItem(s, s.label, s == sort),
                      ],
                    ),
                  ),
                if (onAddFolder != null)
                  Tooltip(
                    message: 'New top-level folder',
                    child: InkWell(
                      onTap: () => onAddFolder!(root),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.create_new_folder_outlined,
                            size: 16, color: TermColors.green,),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: ListView(children: rows)),
        ],
      ),
    );
  }

  PopupMenuItem<FolderSort> _sortItem(FolderSort s, String label, bool on) {
    return PopupMenuItem<FolderSort>(
      value: s,
      child: Text(
        '${on ? "› " : "  "}$label',
        style: mono(
            size: 12, color: on ? TermColors.green : TermColors.text,),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.group,
    required this.depth,
    required this.selected,
    required this.isTrash,
    required this.isRoot,
    required this.onTap,
    this.onAddFolder,
    this.onRenameFolder,
    this.onDeleteFolder,
  });

  final Group group;
  final int depth;
  final bool selected;
  final bool isTrash;
  final bool isRoot;
  final VoidCallback onTap;
  final ValueChanged<Group>? onAddFolder;
  final ValueChanged<Group>? onRenameFolder;
  final ValueChanged<Group>? onDeleteFolder;

  bool get _hasMenu =>
      onAddFolder != null || onRenameFolder != null || onDeleteFolder != null;

  @override
  Widget build(BuildContext context) {
    final count = group.allEntries.length;
    final accent = isTrash ? TermColors.amber : TermColors.green;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? TermColors.surfaceAlt : Colors.transparent,
          border: Border(
            left: BorderSide(
                color: selected ? accent : Colors.transparent, width: 2,),
          ),
        ),
        padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 2),
        child: Row(
          children: [
            Icon(isTrash ? Icons.delete_outline : Icons.folder_outlined,
                size: 14,
                color: selected ? accent : TermColors.textDim,),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  group.name.isEmpty ? '(root)' : group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(
                    size: 13,
                    color: selected ? TermColors.textBright : TermColors.text,
                  ),
                ),
              ),
            ),
            if (count > 0)
              Text('$count',
                  style: mono(size: 11, color: TermColors.textFaint),),
            if (_hasMenu)
              _FolderMenu(
                group: group,
                isRoot: isRoot,
                isTrash: isTrash,
                onAddFolder: onAddFolder,
                onRenameFolder: onRenameFolder,
                onDeleteFolder: onDeleteFolder,
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _FolderMenu extends StatelessWidget {
  const _FolderMenu({
    required this.group,
    required this.isRoot,
    required this.isTrash,
    this.onAddFolder,
    this.onRenameFolder,
    this.onDeleteFolder,
  });
  final Group group;
  final bool isRoot;
  final bool isTrash;
  final ValueChanged<Group>? onAddFolder;
  final ValueChanged<Group>? onRenameFolder;
  final ValueChanged<Group>? onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    // Root can't be renamed or deleted; everything can host a subfolder.
    final canEdit = !isRoot;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 16, color: TermColors.textDim),
      tooltip: 'Folder actions',
      padding: EdgeInsets.zero,
      splashRadius: 18,
      constraints: const BoxConstraints(),
      color: TermColors.surfaceAlt,
      onSelected: (v) {
        switch (v) {
          case 'add':
            onAddFolder?.call(group);
          case 'rename':
            onRenameFolder?.call(group);
          case 'delete':
            onDeleteFolder?.call(group);
        }
      },
      itemBuilder: (_) => [
        if (onAddFolder != null)
          _item('add', Icons.create_new_folder_outlined, 'New subfolder',
              TermColors.text,),
        if (onRenameFolder != null && canEdit)
          _item('rename', Icons.edit_outlined, 'Rename', TermColors.text),
        if (onDeleteFolder != null && canEdit)
          _item('delete', Icons.delete_outline, 'Delete', TermColors.red),
      ],
    );
  }

  PopupMenuItem<String> _item(
      String value, IconData icon, String label, Color color,) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Text(label, style: mono(size: 12, color: color)),
        ],
      ),
    );
  }
}
