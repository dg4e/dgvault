// dgvault — folder (group) tree sidebar: navigate, add/rename/move/delete,
// sort, and drag-to-reorder siblings. Doubles as a read-only picker.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../state/sorting.dart';
import '../theme/terminal_theme.dart';

/// One row in the flattened tree.
class _Node {
  _Node(this.group, this.parent, this.depth);
  final Group group;
  final Group? parent; // null for the root
  final int depth;
}

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
    this.onMoveFolder,
    this.onDeleteFolder,
    this.onReorder,
    this.selectableFilter,
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
  final ValueChanged<Group>? onMoveFolder;
  final ValueChanged<Group>? onDeleteFolder;

  /// Reorder a folder among its siblings (drag). Receives the parent and the
  /// from/to indices into `parent.groups`.
  final void Function(Group parent, int oldIndex, int newIndex)? onReorder;

  /// Picker mode: rows for which this returns false are dimmed and untappable.
  final bool Function(Group group)? selectableFilter;

  List<_Node> _flatten() {
    final out = <_Node>[];
    void walk(Group g, Group? parent, int depth) {
      out.add(_Node(g, parent, depth));
      for (final c in sort.apply(g.groups)) {
        walk(c, g, depth + 1);
      }
    }

    walk(root, null, 0);
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _flatten();
    final reorderable = onReorder != null && sort == FolderSort.manual;

    Widget rowFor(_Node n) {
      final selectable = selectableFilter?.call(n.group) ?? true;
      return _FolderRow(
        key: ValueKey('folder-${n.group.uuid}'),
        group: n.group,
        depth: n.depth,
        selected: identical(n.group, selected) || n.group.uuid == selected.uuid,
        isTrash: n.group.uuid == recycleBinUuid,
        isRoot: identical(n.group, root),
        enabled: selectable,
        draggable: reorderable && n.parent != null,
        index: nodes.indexOf(n),
        onTap: selectable ? () => onSelect(n.group) : null,
        onAddFolder: onAddFolder,
        onRenameFolder: onRenameFolder,
        onMoveFolder: onMoveFolder,
        onDeleteFolder: onDeleteFolder,
      );
    }

    final body = reorderable
        ? ReorderableListView(
            buildDefaultDragHandles: false,
            // onReorder's pre-removal index convention is what _handleReorder's
            // sibling math is built on; keep it over the newer onReorderItem.
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) =>
                _handleReorder(nodes, oldIndex, newIndex),
            children: [for (final n in nodes) rowFor(n)],
          )
        : ListView(children: [for (final n in nodes) rowFor(n)]);

    return Container(
      color: TermColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            sort: sort,
            onSortChanged: onSortChanged,
            onAddRoot: onAddFolder == null ? null : () => onAddFolder!(root),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// Map a flat-list reorder onto a sibling reorder within one parent. Drops
  /// outside the dragged item's sibling run snap to the nearest sibling slot;
  /// re-parenting is done via the explicit "Move to…" action instead.
  void _handleReorder(List<_Node> nodes, int oldIndex, int newIndex) {
    final dragged = nodes[oldIndex];
    final parent = dragged.parent;
    if (parent == null) return; // root can't move
    final siblingFlatIdx = <int>[
      for (var i = 0; i < nodes.length; i++)
        if (identical(nodes[i].parent, parent)) i,
    ];
    final from = siblingFlatIdx.indexOf(oldIndex);
    var to = 0;
    for (final si in siblingFlatIdx) {
      if (si != oldIndex && si < newIndex) to++;
    }
    if (from != to) onReorder!(parent, from, to);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.sort, this.onSortChanged, this.onAddRoot});
  final FolderSort sort;
  final ValueChanged<FolderSort>? onSortChanged;
  final VoidCallback? onAddRoot;

  @override
  Widget build(BuildContext context) {
    final hasMenu = onSortChanged != null || onAddRoot != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 6),
      child: Row(
        children: [
          Text('FOLDERS',
              style: mono(
                  size: 11,
                  color: TermColors.textDim,
                  letterSpacing: 2,
                  weight: FontWeight.w600,),),
          const Spacer(),
          if (hasMenu)
            PopupMenuButton<String>(
              tooltip: 'Folder options',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: TermColors.surfaceAlt,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.more_horiz,
                    size: 18, color: TermColors.textDim,),
              ),
              onSelected: (v) {
                if (v == 'add') {
                  onAddRoot?.call();
                } else {
                  onSortChanged?.call(FolderSort.values.byName(v));
                }
              },
              itemBuilder: (_) => [
                if (onAddRoot != null)
                  _menuRow('add', Icons.create_new_folder_outlined,
                      'New folder', TermColors.text,),
                if (onAddRoot != null && onSortChanged != null)
                  const PopupMenuDivider(),
                if (onSortChanged != null)
                  _sortHeader(),
                if (onSortChanged != null)
                  for (final s in FolderSort.values)
                    _menuRow(s.name, s == sort ? Icons.check : null, s.label,
                        s == sort ? TermColors.green : TermColors.text,),
              ],
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _sortHeader() => PopupMenuItem<String>(
        enabled: false,
        height: 28,
        child: Text('SORT',
            style: mono(
                size: 10, color: TermColors.textFaint, letterSpacing: 1.5,),),
      );

  PopupMenuItem<String> _menuRow(
      String value, IconData? icon, String label, Color color,) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: icon == null
                ? null
                : Icon(icon, size: 15, color: color),
          ),
          Text(label, style: mono(size: 12, color: color)),
        ],
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  const _FolderRow({
    super.key,
    required this.group,
    required this.depth,
    required this.selected,
    required this.isTrash,
    required this.isRoot,
    required this.enabled,
    required this.draggable,
    required this.index,
    required this.onTap,
    this.onAddFolder,
    this.onRenameFolder,
    this.onMoveFolder,
    this.onDeleteFolder,
  });

  final Group group;
  final int depth;
  final bool selected;
  final bool isTrash;
  final bool isRoot;
  final bool enabled;
  final bool draggable;
  final int index;
  final VoidCallback? onTap;
  final ValueChanged<Group>? onAddFolder;
  final ValueChanged<Group>? onRenameFolder;
  final ValueChanged<Group>? onMoveFolder;
  final ValueChanged<Group>? onDeleteFolder;

  bool get hasMenu =>
      onAddFolder != null ||
      onRenameFolder != null ||
      onMoveFolder != null ||
      onDeleteFolder != null;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final count = w.group.allEntries.length;
    final accent = w.isTrash ? TermColors.amber : TermColors.green;
    final showActions = _hover || w.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Opacity(
        opacity: w.enabled ? 1 : 0.35,
        child: InkWell(
          onTap: w.onTap,
          child: Container(
            decoration: BoxDecoration(
              color: w.selected ? TermColors.surfaceAlt : Colors.transparent,
              border: Border(
                left: BorderSide(
                    color: w.selected ? accent : Colors.transparent, width: 2,),
              ),
            ),
            padding: EdgeInsets.only(left: 6.0 + w.depth * 14, right: 4),
            // Fixed height + fixed-width trailing slot so hovering (which swaps
            // the count for the drag handle / menu) never resizes the row.
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  Icon(
                      w.isTrash
                          ? Icons.delete_outline
                          : Icons.folder_outlined,
                      size: 14,
                      color: w.selected ? accent : TermColors.textDim,),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      w.group.name.isEmpty ? '(root)' : w.group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(
                        size: 13,
                        color: w.selected
                            ? TermColors.textBright
                            : TermColors.text,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: showActions
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (w.draggable)
                                ReorderableDragStartListener(
                                  index: w.index,
                                  child: const Icon(Icons.drag_indicator,
                                      size: 16, color: TermColors.textDim,),
                                ),
                              if (w.hasMenu)
                                _FolderMenu(
                                  group: w.group,
                                  isRoot: w.isRoot,
                                  onAddFolder: w.onAddFolder,
                                  onRenameFolder: w.onRenameFolder,
                                  onMoveFolder: w.onMoveFolder,
                                  onDeleteFolder: w.onDeleteFolder,
                                ),
                            ],
                          )
                        : (count > 0
                            ? Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text('$count',
                                      style: mono(
                                          size: 11,
                                          color: TermColors.textFaint,),),
                                ),
                              )
                            : null),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderMenu extends StatelessWidget {
  const _FolderMenu({
    required this.group,
    required this.isRoot,
    this.onAddFolder,
    this.onRenameFolder,
    this.onMoveFolder,
    this.onDeleteFolder,
  });
  final Group group;
  final bool isRoot;
  final ValueChanged<Group>? onAddFolder;
  final ValueChanged<Group>? onRenameFolder;
  final ValueChanged<Group>? onMoveFolder;
  final ValueChanged<Group>? onDeleteFolder;

  @override
  Widget build(BuildContext context) {
    final canEdit = !isRoot; // root can't be renamed / moved / deleted
    // Use child: (not icon:) so there is no IconButton 48px tap target padding
    // that would grow the row height when the menu appears on hover.
    return PopupMenuButton<String>(
      tooltip: 'Folder actions',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      color: TermColors.surfaceAlt,
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(Icons.more_vert, size: 16, color: TermColors.textDim),
      ),
      onSelected: (v) {
        switch (v) {
          case 'add':
            onAddFolder?.call(group);
          case 'rename':
            onRenameFolder?.call(group);
          case 'move':
            onMoveFolder?.call(group);
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
        if (onMoveFolder != null && canEdit)
          _item('move', Icons.drive_file_move_outline, 'Move to…',
              TermColors.text,),
        if (onDeleteFolder != null && canEdit)
          _item('delete', Icons.delete_outline, 'Delete', TermColors.red),
      ],
    );
  }

  PopupMenuItem<String> _item(
      String value, IconData icon, String label, Color color,) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
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
