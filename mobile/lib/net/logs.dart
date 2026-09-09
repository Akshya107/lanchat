List<(String, String)> bootSequence(String name) {
  final upper = name.toUpperCase();
  final title = 'OPERATOR $upper  ·  LATTICE LOCK';
  const sub = 'YOU HAVE CROSSED INTO THE MESH';
  final inner = [title.length, sub.length, 36].reduce((a, b) => a > b ? a : b);
  final bar = '═' * (inner + 2);
  String ctr(String s) => s.padLeft(((inner + s.length) / 2).floor()).padRight(inner);
  return [
    ('boot', ''),
    ('boot', '              ◈  LANCHAT  ·  CHRONO-MESH NODE  ◈'),
    ('boot', '              ░▒▓█  OPENING PHOTONIC UPLINK  █▓▒░'),
    ('boot', ''),
    ('boot', '  > photonic kernel .................. OK'),
    ('boot', '  > temporal lattice ................. CALIBRATED'),
    ('boot', '  > ghost-protocol handshake ......... LOCKED'),
    ('boot', '  > neural lace / operator hash ...... MATCH'),
    ('boot', '  > identity vector .................. $upper'),
    ('boot', '  > mesh horizon ..................... LIVE'),
    ('boot', ''),
    ('hello', '  ╔$bar╗'),
    ('hello', '  ║ ${ctr(title)} ║'),
    ('hello', '  ║ ${ctr(sub)} ║'),
    ('hello', '  ╚$bar╝'),
    ('boot', ''),
    ('boot', '  $upper  ·  the lattice sees you now.'),
    ('boot', '  speak to transmit  ·  /quit collapses this node.'),
    ('boot', ''),
  ];
}