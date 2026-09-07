import 'dart:convert';

import 'package:crypto/crypto.dart';

List<int> _keystream(List<int> key, int n) {
  final out = <int>[];
  var block = sha256.convert(key).bytes;
  while (out.length < n) {
    out.addAll(block);
    block = sha256.convert([...key, ...block]).bytes;
  }
  return out.sublist(0, n);
}

String seal(Map<String, Object?> payload, String room) {
  // Match Python json.dumps(..., separators=(",", ":"), ensure_ascii=False).
  final raw = utf8.encode(jsonEncode(payload));
  final ks = _keystream(utf8.encode(room), raw.length);
  final xored = List<int>.generate(raw.length, (i) => raw[i] ^ ks[i]);
  return base64.encode(xored);
}

Map<String, dynamic>? openPayload(List<int> blob, String room) {
  try {
    final data = base64.decode(utf8.decode(blob));
    final ks = _keystream(utf8.encode(room), data.length);
    final raw = List<int>.generate(data.length, (i) => data[i] ^ ks[i]);
    final obj = jsonDecode(utf8.decode(raw));
    if (obj is Map<String, dynamic>) {
      return obj;
    }
  } catch (_) {}
  return null;
}

String normRoom(String room) {
  final cleaned = room.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return cleaned.length <= 12 ? cleaned : cleaned.substring(0, 12);
}
