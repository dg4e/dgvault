// dgvault — folder (group) tree sidebar.

import 'package:flutter/material.dart';

import 'package:dgvault/core/core.dart';

import '../theme/terminal_theme.dart';

class FolderTree extends StatelessWidget {
  const FolderTree({
    super.key,
    required this.root,
    required this.selected,
    required this.onSelect,
    this.recycleBinUuid,
  });

  final Group root;
  final Group selected;
  final ValueChanged<Group> onSelect;
  final String? recycleBinUuid;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void walk(Group g, int depth) {
      rows.add(_FolderRow(
        group: g,
        depth: depth,
        selected: identical(g, selected) || g.uuid == selected.uuid,
        isTrash: g.uuid == recycleBinUuid,
        onTap: () => onSelect(g),
      ),);
      for (final child in g.groups) {
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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text('// FOLDERS',
                style: mono(size: 11, color: TermColors.textDim, letterSpacing: 1.5),),
          ),
          Expanded(child: ListView(children: rows)),
        ],
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
    required this.onTap,
  });

  final Group group;
  final int depth;
  final bool selected;
  final bool isTrash;
  final VoidCallback onTap;

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
        padding: EdgeInsets.only(
            left: 8.0 + depth * 14, right: 10, top: 8, bottom: 8,),
        child: Row(
          children: [
            Icon(isTrash ? Icons.delete_outline : Icons.folder_outlined,
                size: 14,
                color: selected ? accent : TermColors.textDim,),
            const SizedBox(width: 8),
            Expanded(
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
            if (count > 0)
              Text('$count',
                  style: mono(size: 11, color: TermColors.textFaint),),
          ],
        ),
      ),
    );
  }
}
