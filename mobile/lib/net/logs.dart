import 'dart:math';

final _rng = Random();

const _methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'];
const _levels = ['INFO', 'INFO', 'INFO', 'DEBUG', 'DEBUG', 'WARN'];
const _statuses = [200, 200, 200, 201, 204, 301, 304, 400, 401, 403, 404, 429, 500, 502];
const _paths = [
  '/v1/health',
  '/v1/ready',
  '/v1/metrics',
  '/v1/auth/token',
  '/v1/sessions',
  '/v1/events/batch',
  '/v1/ingest',
  '/v1/cache/keys',
  '/v1/search',
  '/internal/queue/pop',
  '/internal/worker/heartbeat',
  '/graphql',
];
const _ips = [
  '10.0.4.18',
  '10.1.12.8',
  '172.16.3.9',
  '192.168.10.14',
];

String fakeLogLine() {
  final now = DateTime.now().toUtc();
  final stamp =
      '${now.toIso8601String().split('.').first}.${now.millisecond.toString().padLeft(3, '0')}Z';
  var method = _methods[_rng.nextInt(_methods.length)];
  var status = _statuses[_rng.nextInt(_statuses.length)];
  if (method == 'GET' && (status == 201 || status == 204)) {
    status = 200;
  }
  final level = status >= 500 ? 'ERROR' : (status >= 400 ? 'WARN' : _levels[_rng.nextInt(_levels.length)]);
  final ms = [2, 5, 11, 19, 41, 88][_rng.nextInt(6)];
  final req = _rng.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  final path = _paths[_rng.nextInt(_paths.length)].padRight(32);
  return '$stamp  ${level.padRight(5)}  $status  ${method.padRight(6)}  $path  ${ms.toString().padLeft(4)}ms  req_$req  ip=${_ips[_rng.nextInt(_ips.length)]}';
}

List<(String, String)> bootSequence(String name) {
  final upper = name.toUpperCase();
  final title = 'HELLO, $upper';
  const sub = 'YOU ARE NOW IN THE MACHINE';
  final inner = [title.length, sub.length, 28].reduce((a, b) => a > b ? a : b);
  final bar = '═' * (inner + 2);
  String ctr(String s) => s.padLeft(((inner + s.length) / 2).floor()).padRight(inner);
  return [
    ('boot', ''),
    ('boot', '          ░▒▓█  OPENING NEURAL UPLINK  █▓▒░'),
    ('boot', '          ░▒▓█     ACCESSING THE GRID     █▓▒░'),
    ('boot', ''),
    ('boot', '  > bios checksum ................ OK'),
    ('boot', '  > quantum bus sync ............. OK'),
    ('boot', '  > ghost protocol ............... ARMED'),
    ('boot', '  > radio / cell stack ........... SCAN'),
    ('boot', '  > retina / voice hash .......... MATCH'),
    ('boot', '  > operator lock ................ $upper'),
    ('boot', '  > uplink ....................... LIVE'),
    ('boot', ''),
    ('hello', '  ╔$bar╗'),
    ('hello', '  ║ ${ctr(title)} ║'),
    ('hello', '  ║ ${ctr(sub)} ║'),
    ('hello', '  ╚$bar╝'),
    ('boot', ''),
    ('boot', '  welcome back, $name. the grid is listening.'),
    ('boot', '  wifi/hotspot = local.  mobile data = room code.'),
    ('boot', ''),
  ];
}
