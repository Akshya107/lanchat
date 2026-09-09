import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crypto.dart';

const operatorPubHex = '461249261b4fe9959811a8d90796b67581f4ecbf04bd7ec0b11f91ba918441f4';
const _claimPrefix = 'lanchat-claim-v1';
const _prefKey = 'lanchat.master.key';
const _devicePref = 'lanchat.device.id';

List<int> operatorPub() => fromHex(operatorPubHex);

Future<SimpleKeyPair?> skFromHex(String text) async {
  try {
    final raw = fromHex(text);
    if (raw.length != 32) {
      return null;
    }
    final kp = await Ed25519().newKeyPairFromSeed(raw);
    final pub = await kp.extractPublicKey();
    if (toHex(pub.bytes) != operatorPubHex) {
      return null;
    }
    return kp;
  } catch (_) {
    return null;
  }
}

Future<void> saveOperatorKey(String hex) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefKey, hex.trim());
}

Future<SimpleKeyPair?> loadOperatorKey() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_prefKey);
  if (stored == null || stored.isEmpty) {
    return null;
  }
  return skFromHex(stored);
}

Future<SimpleKeyPair?> importOperatorKey(String text) async {
  final sk = await skFromHex(text);
  if (sk == null) {
    return null;
  }
  await saveOperatorKey(text);
  return sk;
}

Future<bool> hasMasterKey() async => await loadOperatorKey() != null;

Future<String> deviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_devicePref);
  if (stored != null && stored.length >= 16) {
    return stored.length <= 32 ? stored : stored.substring(0, 32);
  }
  const hex = '0123456789abcdef';
  final rng = Random.secure();
  final id = List.generate(32, (_) => hex[rng.nextInt(16)]).join();
  await prefs.setString(_devicePref, id);
  return id;
}

List<int> claimMessage(String room, String peerId, int ts, String dhPkHex) {
  return utf8.encode('$_claimPrefix|$room|$peerId|$ts|$dhPkHex');
}

Future<String> signClaim(SimpleKeyPair sk, String room, String peerId, int ts, String dhPkHex) async {
  final sig = await Ed25519().sign(claimMessage(room, peerId, ts, dhPkHex), keyPair: sk);
  return toHex(sig.bytes);
}

Future<bool> verifyClaim(String room, String peerId, int ts, String dhPkHex, String sigHex) async {
  try {
    return await Ed25519().verify(
      claimMessage(room, peerId, ts, dhPkHex),
      signature: Signature(fromHex(sigHex), publicKey: SimplePublicKey(operatorPub(), type: KeyPairType.ed25519)),
    );
  } catch (_) {
    return false;
  }
}
