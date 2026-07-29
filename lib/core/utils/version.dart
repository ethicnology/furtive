/// True when [latest] is a strictly higher version than [current].
///
/// Compares dot-separated numeric components, so `1.2.10` > `1.2.9` — a string
/// comparison gets that pair backwards. Any pre-release or build suffix is
/// ignored (`1.2.0-rc1`, `1.2.0+3` all compare equal to `1.2.0`), and missing
/// trailing components count as zero (`1.2` == `1.2.0`).
///
/// Unparseable input reports "not newer" rather than throwing: the caller gates
/// the post-upgrade changelog on this, and a malformed version in a release
/// entry should show nothing rather than crash on launch.
///
/// Lived in the in-app update check until that feature was removed; the
/// changelog gate is now its only consumer.
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p.replaceAll(RegExp(r'\D'), '')) ?? 0)
      .toList();

  final a = parse(latest);
  final b = parse(current);
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
