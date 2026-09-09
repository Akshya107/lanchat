import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'crypto.dart';
import 'operator.dart';
import 'spam.dart';

class Member {
  Member(this.peerId, this.nick, this.pk, {this.did = ''});
  final String peerId;
  String nick;
  Uint8List pk;
  String did;
}

class RoomCtl {
  RoomCtl({
    required this.peerId,
    required this.nick,
    required this.room,
    required this.dhSk,
    this.operatorSk,
  });

  final String peerId;
  String nick;
  final String room;
  final Uint8List dhSk;
  SimpleKeyPair? operatorSk;
  String? hostId;
  bool locked = false;
  Uint8List? roomKey;
  int epoch = 0;
  final waiting = <String, Member>{};
  final members = <String, Member>{};
  final kicked = <String>{};
  final mutedUntil = <String, double>{};
  final spam = SpamWatch();
  int seenClaimTs = 0;
  Uint8List? dhPk;

  Future<void> ensureDhPk() async {
    dhPk ??= await x25519Public(dhSk);
  }

  String get dhPkHex => toHex(dhPk ?? const []);

  bool get isHost => hostId == peerId;

  bool get admitted => roomKey != null;

  String get mode => locked ? 'private' : 'open';

  void remember(String id, String name, Uint8List? pk, {String did = ''}) {
    if (id.isEmpty || id == peerId || pk == null || pk.length != 32) {
      return;
    }
    final nickName = name.isEmpty ? 'peer' : name;
    if (members.containsKey(id)) {
      members[id]!.nick = nickName;
      members[id]!.pk = pk;
      if (did.isNotEmpty) {
        members[id]!.did = did;
      }
    } else if (waiting.containsKey(id)) {
      waiting[id]!.nick = nickName;
      waiting[id]!.pk = pk;
      if (did.isNotEmpty) {
        waiting[id]!.did = did;
      }
    } else if (!kicked.contains(id)) {
      waiting[id] = Member(id, nickName, pk, did: did);
    }
  }

  void becomeHost() {
    hostId = peerId;
    if (roomKey == null) {
      roomKey = newRoomKey();
      epoch += 1;
    }
    members[peerId] = Member(peerId, nick, dhPk ?? Uint8List(32));
    waiting.remove(peerId);
  }

  Map<String, Object?> hostPayload() => {
        't': 'host',
        'id': peerId,
        'nick': nick,
        'pk': dhPkHex,
        'mode': mode,
        'epoch': epoch,
      };

  Map<String, Object?> askPayload({String did = ''}) {
    final body = <String, Object?>{'t': 'ask', 'id': peerId, 'nick': nick, 'pk': dhPkHex};
    if (did.isNotEmpty) {
      body['did'] = did;
    }
    return body;
  }

  Future<Map<String, Object?>?> claimPayload() async {
    final sk = operatorSk;
    if (sk == null) {
      return null;
    }
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sig = await signClaim(sk, room, peerId, ts, dhPkHex);
    return {'t': 'claim', 'id': peerId, 'nick': nick, 'pk': dhPkHex, 'ts': ts, 'sig': sig};
  }

  Future<bool> acceptKey(String box, int newEpoch) async {
    final key = await unwrapRoomKey(box, dhSk);
    if (key == null) {
      return false;
    }
    roomKey = key;
    if (newEpoch > 0) {
      epoch = newEpoch;
    }
    waiting.remove(peerId);
    members[peerId] = Member(peerId, nick, dhPk ?? Uint8List(32));
    return true;
  }

  Future<bool> takeClaim(Map<String, dynamic> payload) async {
    final id = '${payload['id'] ?? ''}';
    final name = '${payload['nick'] ?? 'operator'}';
    final pkHex = '${payload['pk'] ?? ''}';
    final ts = int.tryParse('${payload['ts'] ?? 0}') ?? 0;
    final sig = '${payload['sig'] ?? ''}';
    if (id.isEmpty || ts <= seenClaimTs) {
      return false;
    }
    if (!await verifyClaim(room, id, ts, pkHex, sig)) {
      return false;
    }
    late final Uint8List pk;
    try {
      pk = fromHex(pkHex);
    } catch (_) {
      return false;
    }
    if (pk.length != 32) {
      return false;
    }
    seenClaimTs = ts;
    hostId = id;
    kicked.remove(id);
    if (id != peerId) {
      members[id] = Member(id, name, pk);
      waiting.remove(id);
    }
    return true;
  }

  bool onHost(Map<String, dynamic> payload) {
    final id = '${payload['id'] ?? ''}';
    if (id.isEmpty || id == peerId) {
      return false;
    }
    if (operatorSk != null && isHost) {
      return false;
    }
    if (isHost && id.compareTo(peerId) > 0) {
      return false;
    }
    final yielded = isHost && id.compareTo(peerId) < 0;
    if (yielded) {
      roomKey = null;
    }
    hostId = id;
    locked = '${payload['mode'] ?? 'open'}' == 'private';
    final nextEpoch = int.tryParse('${payload['epoch'] ?? 0}') ?? 0;
    if (nextEpoch > epoch) {
      epoch = nextEpoch;
    }
    try {
      final pk = fromHex('${payload['pk'] ?? ''}');
      if (pk.length == 32) {
        members[id] = Member(id, '${payload['nick'] ?? 'host'}', pk);
        waiting.remove(id);
      }
    } catch (_) {}
    return yielded;
  }

  Future<String?> wrapFor(Uint8List pk) async {
    final key = roomKey;
    if (key == null || pk.length != 32) {
      return null;
    }
    return wrapRoomKey(key, pk);
  }

  Member? _takeWaiting(String target) {
    if (waiting.containsKey(target)) {
      return waiting.remove(target);
    }
    final want = target.toLowerCase();
    for (final entry in waiting.entries.toList()) {
      if (entry.value.nick.toLowerCase() == want) {
        return waiting.remove(entry.key);
      }
    }
    return members[target];
  }

  Future<List<Map<String, Object?>>> admitPayloads(String target) async {
    final member = _takeWaiting(target);
    if (member == null || roomKey == null) {
      return [];
    }
    kicked.remove(member.peerId);
    _clearMute(member);
    members[member.peerId] = member;
    final box = await wrapFor(member.pk);
    if (box == null) {
      return [];
    }
    return [
      {'t': 'admit', 'to': member.peerId, 'epoch': epoch, 'box': box}
    ];
  }

  Map<String, Object?>? denyPayload(String target) {
    final member = _takeWaiting(target);
    if (member == null) {
      return null;
    }
    waiting.remove(member.peerId);
    return {'t': 'deny', 'to': member.peerId};
  }

  Member? _findMember(String target) {
    if (members.containsKey(target)) {
      return members[target];
    }
    final want = target.toLowerCase();
    for (final row in members.values) {
      if (row.nick.toLowerCase() == want && row.peerId != peerId) {
        return row;
      }
    }
    return null;
  }

  Future<List<Map<String, Object?>>> kickPayloads(String target, {bool spam = false}) async {
    final member = _findMember(target);
    if (member == null || member.peerId == peerId) {
      return [];
    }
    members.remove(member.peerId);
    waiting.remove(member.peerId);
    if (spam) {
      _mute(member, SpamWatch.banSec);
    } else {
      kicked.add(member.peerId);
    }
    roomKey = newRoomKey();
    epoch += 1;
    final kick = <String, Object?>{'t': 'kick', 'to': member.peerId};
    if (spam) {
      kick['why'] = 'spam';
      kick['sec'] = SpamWatch.banSec;
    }
    final out = <Map<String, Object?>>[kick];
    for (final row in members.values) {
      if (row.peerId == peerId) {
        continue;
      }
      final box = await wrapFor(row.pk);
      if (box != null) {
        out.add({'t': 'rekey', 'to': row.peerId, 'epoch': epoch, 'box': box});
      }
    }
    return out;
  }

  Future<Map<String, Object?>?> autoAdmitPayload(Member member) async {
    if (roomKey == null) {
      return null;
    }
    waiting.remove(member.peerId);
    members[member.peerId] = member;
    final box = await wrapFor(member.pk);
    if (box == null) {
      return null;
    }
    return {'t': 'admit', 'to': member.peerId, 'epoch': epoch, 'box': box};
  }

  Future<Map<String, Object?>?> handoffPayload(String toId) async {
    final row = members[toId] ?? waiting[toId];
    if (row == null || roomKey == null) {
      return null;
    }
    final box = await wrapFor(row.pk);
    if (box == null) {
      return null;
    }
    return {'t': 'handoff', 'to': toId, 'epoch': epoch, 'box': box};
  }

  bool isMuted(String id, String name, Uint8List? pk, {String did = ''}) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final keys = <String>[id, name.toLowerCase()];
    if (pk != null && pk.length == 32) {
      keys.add(toHex(pk));
    }
    if (did.isNotEmpty) {
      keys.add(did);
    }
    return keys.any((k) => k.isNotEmpty && (mutedUntil[k] ?? 0) > now);
  }

  int muteLeft(String id, String name, Uint8List? pk, {String did = ''}) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final keys = <String>[id, name.toLowerCase()];
    if (pk != null && pk.length == 32) {
      keys.add(toHex(pk));
    }
    if (did.isNotEmpty) {
      keys.add(did);
    }
    var left = 0.0;
    for (final k in keys) {
      if (k.isEmpty) {
        continue;
      }
      left = left < ((mutedUntil[k] ?? 0) - now) ? (mutedUntil[k] ?? 0) - now : left;
    }
    return left <= 0 ? 0 : left.ceil();
  }

  void _mute(Member member, int seconds) {
    final until = DateTime.now().millisecondsSinceEpoch / 1000.0 + seconds;
    mutedUntil[member.peerId] = until;
    mutedUntil[member.nick.toLowerCase()] = until;
    mutedUntil[toHex(member.pk)] = until;
    if (member.did.isNotEmpty) {
      mutedUntil[member.did] = until;
    }
    spam.forget(member.peerId);
  }

  void _clearMute(Member member) {
    mutedUntil.remove(member.peerId);
    mutedUntil.remove(member.nick.toLowerCase());
    mutedUntil.remove(toHex(member.pk));
    if (member.did.isNotEmpty) {
      mutedUntil.remove(member.did);
    }
  }
}
