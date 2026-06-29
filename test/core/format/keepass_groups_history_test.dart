// Sanity: nested groups (folders) parse into the tree, entry History does NOT
// leak into the visible entry list, and the Recycle Bin is its own group.

import 'package:dgvault/core/core.dart';
import 'package:test/test.dart';

const _xml = '''
<KeePassFile><Meta><DatabaseName>db</DatabaseName></Meta><Root>
<Group><UUID>cm9vdA==</UUID><Name>Root</Name>
  <Group><UUID>cA==</UUID><Name>Personal</Name>
    <Entry><UUID>ZTE=</UUID>
      <String><Key>Title</Key><Value>GitHub</Value></String>
      <History>
        <Entry><UUID>ZTE=</UUID><String><Key>Title</Key><Value>GitHub OLD</Value></String></Entry>
        <Entry><UUID>ZTE=</UUID><String><Key>Title</Key><Value>GitHub OLDER</Value></String></Entry>
      </History>
    </Entry>
  </Group>
  <Group><UUID>dw==</UUID><Name>Work</Name>
    <Entry><UUID>ZTI=</UUID><String><Key>Title</Key><Value>Jira</Value></String></Entry>
  </Group>
  <Group><UUID>cmI=</UUID><Name>Recycle Bin</Name>
    <Entry><UUID>ZTM=</UUID><String><Key>Title</Key><Value>Deleted</Value></String></Entry>
  </Group>
</Group>
</Root></KeePassFile>''';

void main() {
  final db = const KeePassXml().decode(_xml);

  test('nested groups (folders) are parsed into the tree', () {
    final root = db.root;
    expect(root.name, 'Root');
    expect(root.groups.map((g) => g.name),
        containsAll(['Personal', 'Work', 'Recycle Bin']),);
    final personal = root.groups.firstWhere((g) => g.name == 'Personal');
    expect(personal.entries.single.title, 'GitHub');
  });

  test('entry History does NOT appear as a separate entry', () {
    final titles = db.root.allEntries.map((e) => e.title).toList();
    // Only the 3 current entries — no "GitHub OLD"/"OLDER" from history.
    expect(titles, containsAll(['GitHub', 'Jira', 'Deleted']));
    expect(titles.where((t) => t == 'GitHub').length, 1);
    expect(titles.any((t) => t!.contains('OLD')), isFalse);

    // History is preserved on the entry itself.
    final github = db.root.allEntries.firstWhere((e) => e.title == 'GitHub');
    expect(github.history.length, 2);
  });
}
