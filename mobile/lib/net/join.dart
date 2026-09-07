import 'dart:math';

const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

String newRoomCode() {
  final rng = Random.secure();
  return List.generate(6, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
}

String newPeerId() {
  final rng = Random.secure();
  const hex = '0123456789abcdef';
  return List.generate(32, (_) => hex[rng.nextInt(16)]).join();
}

String newMessageId() {
  final rng = Random.secure();
  const hex = '0123456789abcdef';
  return List.generate(12, (_) => hex[rng.nextInt(16)]).join();
}

String encodeJoin(String ip, int port) {
  final parts = ip.split('.').map(int.parse).toList();
  if (parts.length != 4) {
    throw const FormatException('need IPv4');
  }
  var n = (parts[0] << 40) |
      (parts[1] << 32) |
      (parts[2] << 24) |
      (parts[3] << 16) |
      (port & 0xFFFF);
  final chars = <String>[];
  for (var i = 0; i < 10; i++) {
    chars.add(alphabet[n & 31]);
    n >>= 5;
  }
  final raw = chars.reversed.join();
  return '${raw.substring(0, 4)}-${raw.substring(4, 8)}-${raw.substring(8, 10)}';
}

(String, int) decodeJoin(String code) {
  final index = {for (var i = 0; i < alphabet.length; i++) alphabet[i]: i};
  final raw = code.toUpperCase().split('').where(index.containsKey).join();
  if (raw.length != 10) {
    throw const FormatException('bad code');
  }
  var n = 0;
  for (final ch in raw.split('')) {
    n = (n << 5) | index[ch]!;
  }
  final port = n & 0xFFFF;
  final d = (n >> 16) & 0xFF;
  final c = (n >> 24) & 0xFF;
  final b = (n >> 32) & 0xFF;
  final a = (n >> 40) & 0xFF;
  if (port == 0 || a == 0) {
    throw const FormatException('bad code');
  }
  return ('$a.$b.$c.$d', port);
}

(String, int) parseTarget(String raw) {
  final text = raw.trim();
  if (text.contains(':') && text.split(':').first.contains('.')) {
    final i = text.lastIndexOf(':');
    return (text.substring(0, i).trim(), int.parse(text.substring(i + 1)));
  }
  return decodeJoin(text);
}
