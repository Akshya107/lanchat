import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const wrapSalt = [108, 97, 110, 99, 104, 97, 116, 45, 119, 114, 97, 112, 45, 118, 49]; // lanchat-wrap-v1
const wrapInfo = [114, 111, 111, 109, 45, 107, 101, 121]; // room-key
const wrapVersion = 1;

String normRoom(String room) {
  final cleaned = room.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return cleaned.length <= 12 ? cleaned : cleaned.substring(0, 12);
}

Uint8List fromHex(String text) {
  final clean = text.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String toHex(List<int> data) {
  return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _random(int n) {
  final rng = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
}

Future<(Uint8List, Uint8List)> newX25519() async {
  final algo = X25519();
  final kp = await algo.newKeyPair();
  final pk = await kp.extractPublicKey();
  final sk = await kp.extractPrivateKeyBytes();
  return (Uint8List.fromList(sk), Uint8List.fromList(pk.bytes));
}

Future<Uint8List> x25519Public(Uint8List sk) async {
  final kp = await X25519().newKeyPairFromSeed(sk);
  final pk = await kp.extractPublicKey();
  return Uint8List.fromList(pk.bytes);
}

Uint8List newRoomKey() => _random(32);

Future<Uint8List> _hkdf(List<int> shared) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final key = await hkdf.deriveKey(
    secretKey: SecretKey(shared),
    nonce: wrapSalt,
    info: wrapInfo,
  );
  return Uint8List.fromList(await key.extractBytes());
}

Future<String> wrapRoomKey(Uint8List roomKey, Uint8List recipientPk) async {
  final algo = X25519();
  final eph = await algo.newKeyPair();
  final ephPk = await eph.extractPublicKey();
  final shared = await algo.sharedSecretKey(
    keyPair: eph,
    remotePublicKey: SimplePublicKey(recipientPk, type: KeyPairType.x25519),
  );
  final wrapKey = await _hkdf(await shared.extractBytes());
  final nonce = _random(12);
  final box = await AesGcm.with256bits().encrypt(roomKey, secretKey: SecretKey(wrapKey), nonce: nonce);
  final out = BytesBuilder()
    ..addByte(wrapVersion)
    ..add(ephPk.bytes)
    ..add(nonce)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return base64Encode(out.toBytes());
}

Future<Uint8List?> unwrapRoomKey(String boxB64, Uint8List recipientSk) async {
  try {
    final raw = base64Decode(boxB64);
    if (raw.length < 1 + 32 + 12 + 16 || raw[0] != wrapVersion) {
      return null;
    }
    final ephPk = raw.sublist(1, 33);
    final nonce = raw.sublist(33, 45);
    final rest = raw.sublist(45);
    final ct = rest.sublist(0, rest.length - 16);
    final mac = rest.sublist(rest.length - 16);
    final algo = X25519();
    final kp = await algo.newKeyPairFromSeed(recipientSk);
    final shared = await algo.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: SimplePublicKey(ephPk, type: KeyPairType.x25519),
    );
    final wrapKey = await _hkdf(await shared.extractBytes());
    final clear = await AesGcm.with256bits().decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(wrapKey),
    );
    if (clear.length != 32) {
      return null;
    }
    return Uint8List.fromList(clear);
  } catch (_) {
    return null;
  }
}

List<int> _aad(String room) => utf8.encode('ec/v2/$room/m');

String _dumps(Map<String, Object?> payload) => jsonEncode(payload);

Future<String> sealChat(Map<String, Object?> payload, String room, Uint8List roomKey) async {
  final nonce = _random(12);
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(_dumps(payload)),
    secretKey: SecretKey(roomKey),
    nonce: nonce,
    aad: _aad(room),
  );
  final out = BytesBuilder()
    ..add(nonce)
    ..add(box.cipherText)
    ..add(box.mac.bytes);
  return base64Encode(out.toBytes());
}

Future<Map<String, dynamic>?> openChat(List<int> blob, String room, Uint8List roomKey) async {
  try {
    var data = blob;
    try {
      data = base64Decode(utf8.decode(blob));
    } catch (_) {
      try {
        data = base64Decode(String.fromCharCodes(blob));
      } catch (_) {}
    }
    if (data.length < 12 + 16) {
      return null;
    }
    final nonce = data.sublist(0, 12);
    final rest = data.sublist(12);
    final ct = rest.sublist(0, rest.length - 16);
    final mac = rest.sublist(rest.length - 16);
    final raw = await AesGcm.with256bits().decrypt(
      SecretBox(ct, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(roomKey),
      aad: _aad(room),
    );
    final obj = jsonDecode(utf8.decode(raw));
    if (obj is Map<String, dynamic>) {
      return obj;
    }
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> openChatB64(String blob, String room, Uint8List roomKey) {
  return openChat(utf8.encode(blob), room, roomKey);
}
