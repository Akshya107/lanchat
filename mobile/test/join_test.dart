import 'package:flutter_test/flutter_test.dart';
import 'package:lanchat_mobile/net/crypto.dart';
import 'package:lanchat_mobile/net/join.dart';

void main() {
  test('LAN join codes round-trip like the CLI', () {
    final code = encodeJoin('192.168.1.10', 1234);
    expect(code.contains('-'), isTrue);
    final decoded = decodeJoin(code);
    expect(decoded.$1, '192.168.1.10');
    expect(decoded.$2, 1234);
    expect(parseTarget('192.168.1.10:48700').$2, 48700);
  });

  test('room AES-GCM seal opens', () async {
    final key = newRoomKey();
    const room = 'AB12CD';
    final sealed = await sealChat({'t': 'hello', 'id': 'abc', 'nick': 'Ada'}, room, key);
    final opened = await openChatB64(sealed, room, key);
    expect(opened?['t'], 'hello');
    expect(opened?['nick'], 'Ada');
    expect(normRoom('ab-12-cd'), 'AB12CD');
  });
}
