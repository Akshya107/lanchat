class SpamWatch {
  SpamWatch();

  static const banSec = 30;
  static const burstN = 4;
  static const burstSec = 2.0;
  static const repeatN = 3;
  static const repeatSec = 10.0;
  static const rapidN = 3;
  static const rapidGap = 0.4;

  final _events = <String, List<(double, String)>>{};

  bool note(String who, String text) {
    if (who.isEmpty) {
      return false;
    }
    final line = text.toLowerCase().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).join(' ');
    if (line.isEmpty) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final q = _events.putIfAbsent(who, () => <(double, String)>[]);
    q.add((now, line));
    q.removeWhere((e) => now - e.$1 > repeatSec);
    if (q.where((e) => now - e.$1 <= burstSec).length >= burstN) {
      return true;
    }
    if (q.where((e) => e.$2 == line).length >= repeatN) {
      return true;
    }
    if (q.length >= rapidN) {
      final times = q.sublist(q.length - rapidN).map((e) => e.$1).toList();
      var rapid = true;
      for (var i = 1; i < times.length; i++) {
        if (times[i] - times[i - 1] > rapidGap) {
          rapid = false;
          break;
        }
      }
      if (rapid) {
        return true;
      }
    }
    return false;
  }

  void forget(String who) {
    _events.remove(who);
  }
}
