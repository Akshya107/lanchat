import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lanchat_mobile/net/crypto.dart';
import 'package:lanchat_mobile/net/operator.dart';

void main() {
  test('unwraps a Python X25519+AES room-key box', () async {
    final sk = fromHex('11' * 32);
    final roomKey = fromHex('22' * 32);
    const box =
        'AcpM9yo/6HnND7/Zc+5jIDdRrQYpj0A4Ekeh6PK3WwAkSNZ6FnHlKC6syKjOG76Ilwe7wNc3DnfdFIGWlRyJ0OB4QFiXG3YPDy69bqhjRwZazuwSfWPUnwYRXD+Q';
    final got = await unwrapRoomKey(box, sk);
    expect(got, isNotNull);
    expect(toHex(got!), toHex(roomKey));
  });

  test('opens a Python AES-GCM chat blob', () async {
    final roomKey = fromHex('22' * 32);
    const blob = 'mn6Qan+Oz2dvt16Bey7ntncInJ6IEqAx/vvU3P/GFEjORdkO8fSks/DNcIU1RizbV6LbRdrT9CXXJlnhyt8=';
    final payload = await openChat(utf8.encode(blob), 'ROOM01', roomKey);
    expect(payload?['text'], 'hi');
  });

  test('dart wrap round-trips', () async {
    final pair = await newX25519();
    final roomKey = newRoomKey();
    final box = await wrapRoomKey(roomKey, pair.$2);
    final got = await unwrapRoomKey(box, pair.$1);
    expect(got, isNotNull);
    expect(toHex(got!), toHex(roomKey));
  });

  test('verifies a Python operator claim', () async {
    final pkHex = 'aa' * 32;
    const sig =
        '1749f84e97c61eb3ef3d0d1f9e34cfa449de7cfa94bd2f0d94d15e134c4de6a0b9d110eaecb5d4548597a961e3e575ed77300f6a2fa7c6c077fa889a8c4bb108';
    final ok = await verifyClaim('ROOM01', 'deadbeefcafebabe', 1700000000, pkHex, sig);
    expect(ok, isTrue);
  });
}
