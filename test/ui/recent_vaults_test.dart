// Recent-vaults ordering: newest-first, deduped by location, capped. (The
// JSON file IO is path_provider-backed and exercised on-device; the ordering
// logic — the only real logic — is pure and tested here.)

import 'package:dgvault/ui/state/recent_vaults.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> locs(List<RecentVault> l) => l.map((r) => r.location).toList();

void main() {
  test('merged promotes the newest to the front', () {
    final out = RecentVaults.merged(
      const [RecentVault('/a', 'a'), RecentVault('/b', 'b')],
      '/c',
      'c',
    );
    expect(locs(out), ['/c', '/a', '/b']);
  });

  test('merged dedupes by location (re-open moves it to the front)', () {
    final out = RecentVaults.merged(
      const [RecentVault('/a', 'a'), RecentVault('/b', 'b')],
      '/b',
      'b',
    );
    expect(locs(out), ['/b', '/a']); // no duplicate /b
  });

  test('merged caps at maxEntries, dropping the oldest', () {
    var list = <RecentVault>[];
    for (var i = 0; i < RecentVaults.maxEntries + 3; i++) {
      list = RecentVaults.merged(list, '/vault$i', 'vault$i');
    }
    expect(list.length, RecentVaults.maxEntries);
    // The three most recent are at the front; the oldest fell off.
    expect(list.first.location, '/vault${RecentVaults.maxEntries + 2}');
    expect(locs(list), isNot(contains('/vault0')));
  });
}
