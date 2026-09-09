import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'models/line.dart';
import 'net/crypto.dart';
import 'net/join.dart';
import 'net/lan.dart';
import 'net/logs.dart';
import 'net/operator.dart';
import 'net/room_ctl.dart';
import 'net/spam.dart';
import 'net/wan.dart';

class ChatSession extends ChangeNotifier {
  ChatSession({required this.nick, this.roomHint = '', this.masterKeyHex = ''});

  String nick;
  final String roomHint;
  final String masterKeyHex;
  final peerId = newPeerId();
  String did = '';
  late final String roomSeed = roomHint.length >= 4 ? normRoom(roomHint) : newRoomCode();
  String room = '';
  String localIp = '0.0.0.0';
  String transport = 'scan';
  int tcpPort = 0;
  bool muted = false;
  bool running = false;
  bool kicked = false;

  final lines = <TermLine>[];
  final typists = <String, DateTime>{};
  final _seen = <String>{};

  LanMesh? _lan;
  WanRoom? _wan;
  RoomCtl? ctl;
  Uint8List? _dhSk;
  SimpleKeyPair? _operatorSk;
  Timer? _typingExpire;
  Timer? _hostBeacon;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _typingOn = false;

  bool get waitingOutside => ctl != null && !ctl!.admitted;

  String get joinCode {
    try {
      if (tcpPort == 0) {
        return '';
      }
      return encodeJoin(localIp, tcpPort);
    } catch (_) {
      return '';
    }
  }

  String get status {
    final token = joinCode.replaceAll('-', '');
    final role = ctl?.isHost == true ? 'host' : 'guest';
    final mode = ctl?.mode ?? 'open';
    final waitN = ctl?.waiting.length ?? 0;
    final lobby = waitingOutside ? '  lobby' : '';
    return '⟨ NODE ⟩  $localIp  path=$transport  room=$room  $role  $mode  waiting=$waitN$lobby  token=$token  ⟨ LIVE ⟩';
  }

  String get typingLabel {
    if (waitingOutside) {
      return '';
    }
    final now = DateTime.now();
    final names = typists.entries.where((e) => now.difference(e.value).inMilliseconds < 2400).map((e) => e.key).toList();
    if (names.isEmpty) {
      return '';
    }
    if (names.length == 1) {
      return '⋯ ${names.first} is weaving a thought';
    }
    return '⋯ ${names.join(', ')} are weaving thoughts';
  }

  Future<void> start() async {
    running = true;
    room = roomSeed;
    did = await deviceId();
    final dh = await newX25519();
    _dhSk = dh.$1;
    if (masterKeyHex.trim().isNotEmpty) {
      _operatorSk = await importOperatorKey(masterKeyHex);
    } else {
      _operatorSk = await loadOperatorKey();
    }
    await _detectPath();
    _lan = LanMesh(
      peerId: peerId,
      nick: nick,
      room: room,
      dhPkHex: toHex(dh.$2),
      getRoomKey: () => ctl?.roomKey,
      onChat: _onChat,
      onJoin: (id, name) {
        _sys('node=$name event=register region=local');
      },
      onLeave: (id, name) {
        typists.remove(name);
        _sys('node=$name event=drain region=local');
        notifyListeners();
      },
      onTyping: setTyping,
    );
    try {
      tcpPort = await _lan!.start();
    } catch (_) {
      tcpPort = 0;
    }
    localIp = await _bestLocalIp();
    unawaited(_opening());
    _typingExpire = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  Future<void> _detectPath() async {
    try {
      final result = await Connectivity().checkConnectivity();
      final hasWifi = result.contains(ConnectivityResult.wifi);
      final hasCell = result.contains(ConnectivityResult.mobile);
      final hasEth = result.contains(ConnectivityResult.ethernet);
      if (hasWifi || hasEth) {
        transport = 'wifi';
      } else if (hasCell) {
        transport = 'cell';
      } else {
        transport = 'offline';
      }
    } catch (_) {
      transport = Platform.isIOS || Platform.isAndroid ? 'radio' : 'local';
    }
  }

  Future<void> _opening() async {
    for (final frame in bootSequence(nick)) {
      if (!running) {
        return;
      }
      final kind = switch (frame.$1) {
        'hello' => LineKind.hello,
        _ => LineKind.boot,
      };
      lines.add(TermLine(kind, frame.$2));
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    _showCodes();
    await joinRoom(room);
  }

  void _showCodes() {
    if (tcpPort > 0 && !localIp.startsWith('0.')) {
      try {
        final code = encodeJoin(localIp, tcpPort);
        _sys('join $code   ($localIp:$tcpPort)  wifi/hotspot');
      } catch (_) {}
    }
    _sys('room $room   mobile data / any internet: /room $room');
  }

  void _sys(String text) {
    lines.add(TermLine(LineKind.sys, text));
    notifyListeners();
  }

  void _onChat(String name, String text, String mid, String id) {
    if (waitingOutside) {
      return;
    }
    final c = ctl;
    if (c != null && c.isHost && id.isNotEmpty && id != peerId) {
      if (c.spam.note(id, text)) {
        unawaited(_spamKick(id, name));
        return;
      }
    }
    if (mid.isNotEmpty) {
      if (_seen.contains(mid)) {
        return;
      }
      _seen.add(mid);
    }
    if (text.isEmpty) {
      return;
    }
    typists.remove(name);
    lines.add(TermLine(LineKind.chat, text, nick: name));
    notifyListeners();
  }

  Future<void> _spamKick(String id, String name) async {
    final c = ctl;
    if (c == null || !c.isHost) {
      return;
    }
    final payloads = await c.kickPayloads(id.isNotEmpty ? id : name, spam: true);
    if (payloads.isEmpty) {
      return;
    }
    _syncKey();
    for (final payload in payloads) {
      _signal(payload);
    }
    _sys('kicked $name  spam  wait ${SpamWatch.banSec}s');
  }

  void setTyping(String name, bool on) {
    if (waitingOutside || name.isEmpty) {
      return;
    }
    if (on) {
      typists[name] = DateTime.now();
    } else {
      typists.remove(name);
    }
    notifyListeners();
  }

  void localTyping(bool on) {
    if (waitingOutside) {
      return;
    }
    final now = DateTime.now();
    if (on && _typingOn && now.difference(_lastTypingSent).inMilliseconds < 400) {
      return;
    }
    if (!on && !_typingOn) {
      return;
    }
    _typingOn = on;
    _lastTypingSent = now;
    _lan?.sendTyping(on);
    unawaited(_wan?.publishChat({'t': 'typing', 'on': on}) ?? Future.value());
  }

  bool _hostOnly() {
    if (ctl?.isHost == true) {
      return true;
    }
    _sys('host only');
    return false;
  }

  void _signal(Map<String, Object?> payload) {
    _wan?.publishSignal(payload);
  }

  void _syncKey() {
    _wan?.setRoomKey(ctl?.roomKey);
  }

  void _startHostBeacon() {
    _hostBeacon?.cancel();
    _hostBeacon = Timer.periodic(const Duration(seconds: 8), (_) {
      final c = ctl;
      if (c == null || !c.isHost) {
        return;
      }
      _wan?.publishSignal(c.hostPayload());
    });
  }

  Future<void> submit(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) {
      return;
    }
    localTyping(false);
    final lower = text.toLowerCase();
    if (lower == '/clear' || lower == 'cls' || lower == '/cls') {
      lines.clear();
      notifyListeners();
      return;
    }
    if (lower == '/quit' || lower == '/exit' || lower == '/q') {
      await stop();
      return;
    }
    if (lower == '/help' || lower == '/?') {
      _sys('slash: /join /room /lock /open /admit NAME /deny NAME /kick NAME /waiting /claim KEY /master /host /code /clear /nick /mute /quit');
      return;
    }
    if (lower == '/code' || lower == '/listen') {
      _showCodes();
      return;
    }
    if (lower == '/peers') {
      _sys('path=$transport room=$room');
      return;
    }
    if (lower == '/host') {
      final c = ctl;
      if (c == null) {
        _sys('no room yet');
        return;
      }
      final role = c.isHost ? 'host' : 'guest';
      final door = c.admitted ? 'admitted' : 'waiting outside';
      _sys('you=$role  room=$room  ${c.mode}  $door');
      return;
    }
    if (lower == '/master') {
      _sys(await hasMasterKey() ? 'master key on this device' : 'no master key on this device');
      return;
    }
    if (lower == '/waiting') {
      if (!_hostOnly()) {
        return;
      }
      final names = ctl!.waiting.values.map((m) => m.nick).join(', ');
      _sys(names.isEmpty ? 'door is empty' : 'waiting: $names');
      return;
    }
    if (lower == '/lock' || lower == '/private') {
      if (!_hostOnly()) {
        return;
      }
      ctl!.locked = true;
      _signal({'t': 'mode', 'mode': 'private'});
      _signal(ctl!.hostPayload());
      _sys('room private  newcomers wait outside');
      return;
    }
    if (lower == '/open' || lower == '/unlock') {
      if (!_hostOnly()) {
        return;
      }
      ctl!.locked = false;
      _signal({'t': 'mode', 'mode': 'open'});
      _signal(ctl!.hostPayload());
      for (final member in ctl!.waiting.values.toList()) {
        final payload = await ctl!.autoAdmitPayload(member);
        if (payload != null) {
          _signal(payload);
        }
      }
      _sys('room open');
      return;
    }
    if (lower.startsWith('/admit')) {
      if (!_hostOnly()) {
        return;
      }
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('usage: /admit NAME');
        return;
      }
      final payloads = await ctl!.admitPayloads(parts.sublist(1).join(' '));
      if (payloads.isEmpty) {
        _sys('no one by that name at the door');
        return;
      }
      for (final payload in payloads) {
        _signal(payload);
      }
      _sys('admitted ${parts.sublist(1).join(' ')}');
      return;
    }
    if (lower.startsWith('/deny')) {
      if (!_hostOnly()) {
        return;
      }
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('usage: /deny NAME');
        return;
      }
      final payload = ctl!.denyPayload(parts.sublist(1).join(' '));
      if (payload == null) {
        _sys('no one by that name at the door');
        return;
      }
      _signal(payload);
      _sys('denied ${parts.sublist(1).join(' ')}');
      return;
    }
    if (lower.startsWith('/kick')) {
      if (!_hostOnly()) {
        return;
      }
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('usage: /kick NAME');
        return;
      }
      final payloads = await ctl!.kickPayloads(parts.sublist(1).join(' '));
      if (payloads.isEmpty) {
        _sys('no one by that name in the room');
        return;
      }
      _syncKey();
      for (final payload in payloads) {
        _signal(payload);
      }
      _sys('kicked ${parts.sublist(1).join(' ')}');
      return;
    }
    if (lower.startsWith('/claim')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('usage: /claim KEY   paste the master key');
        return;
      }
      final sk = await importOperatorKey(parts.sublist(1).join(' '));
      if (sk == null) {
        _sys('claim failed');
        return;
      }
      _operatorSk = sk;
      final c = ctl;
      if (c != null) {
        c.operatorSk = sk;
        c.hostId = peerId;
        final claim = await c.claimPayload();
        if (claim != null) {
          _signal(claim);
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        c.becomeHost();
        _syncKey();
        _signal(c.hostPayload());
        _startHostBeacon();
      }
      _sys('you hold this room');
      return;
    }
    if (lower == '/mute') {
      muted = true;
      _sys('ting muted');
      return;
    }
    if (lower == '/unmute') {
      muted = false;
      _sys('ting on');
      return;
    }
    if (lower.startsWith('/nick')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('usage: /nick NAME');
        notifyListeners();
        return;
      }
      nick = parts.sublist(1).join(' ').trim();
      _lan?.nick = nick;
      _wan?.nick = nick;
      ctl?.nick = nick;
      _lan?.broadcast({'t': 'nick', 'id': peerId, 'nick': nick});
      _sys('operator=$nick');
      return;
    }
    if (lower.startsWith('/room')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('room $room   friend types: /room $room');
        return;
      }
      await joinRoom(parts[1]);
      return;
    }
    if (lower.startsWith('/join')) {
      final parts = text.split(RegExp(r'\s+'));
      if (parts.length < 2) {
        _sys('usage: /join ROOM  or  /join LAN-CODE');
        return;
      }
      await _joinTarget(parts.sublist(1).join(' '));
      return;
    }
    if (text.startsWith('/')) {
      _sys('unknown command ${text.split(' ').first}');
      return;
    }
    if (waitingOutside) {
      _sys('waiting outside  host has not let you in');
      return;
    }
    final mid = newMessageId();
    await _lan?.sendChat(text, mid);
    await _wan?.publishChat({'t': 'chat', 'text': text, 'mid': mid});
    lines.add(TermLine(LineKind.chat, text, nick: nick, mine: true));
    notifyListeners();
  }

  Future<void> _joinTarget(String raw) async {
    final compact = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (compact.length >= 4 && compact.length <= 8 && !raw.contains(':') && !raw.contains('.')) {
      await joinRoom(compact);
      return;
    }
    try {
      final target = parseTarget(raw);
      final ok = await _lan?.connectHost(target.$1, target.$2) ?? false;
      _sys(ok ? 'joined ${target.$1}:${target.$2}' : 'join failed ${target.$1}:${target.$2}');
    } catch (_) {
      _sys('bad join code');
    }
  }

  Future<void> joinRoom(String code) async {
    room = normRoom(code);
    if (room.length < 4) {
      _sys('room code too short');
      return;
    }
    _hostBeacon?.cancel();
    await _wan?.close();
    final dhSk = _dhSk;
    if (dhSk == null) {
      return;
    }
    _lan?.room = room;
    ctl = RoomCtl(peerId: peerId, nick: nick, room: room, dhSk: dhSk, operatorSk: _operatorSk);
    await ctl!.ensureDhPk();
    _wan = WanRoom(peerId: peerId, nick: nick, room: room, onPayload: _onWan);
    final ok = await _wan!.connect();
    if (!ok) {
      _wan = null;
      _sys('room offline  no internet / cell blocked mqtt?');
      return;
    }
    _sys('room $room  internet on  ($transport)');
    await _enterRoom();
  }

  Future<void> _enterRoom() async {
    final c = ctl;
    final wan = _wan;
    if (c == null || wan == null) {
      return;
    }
    if (c.operatorSk != null) {
      final claim = await c.claimPayload();
      if (claim != null) {
        wan.publishSignal(claim);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!running || ctl != c) {
        return;
      }
      c.becomeHost();
      _syncKey();
      wan.publishSignal(c.hostPayload());
      _sys('you hold this room  (master key)');
      _startHostBeacon();
      notifyListeners();
      return;
    }
    wan.publishSignal(c.askPayload(did: did));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!running || ctl != c) {
      return;
    }
    if (c.hostId == null) {
      c.becomeHost();
      _syncKey();
      wan.publishSignal(c.hostPayload());
      _sys('you are host of this room');
      _startHostBeacon();
    } else if (c.admitted) {
      _sys('in the room');
    } else if (c.locked) {
      _sys('waiting outside  host must /admit you');
    } else {
      _sys('knocking  waiting for host key');
    }
    notifyListeners();
  }

  void _onWan(Map<String, dynamic> payload, String channel) {
    unawaited(_handleWan(payload, channel));
  }

  Future<void> _handleWan(Map<String, dynamic> payload, String channel) async {
    final c = ctl;
    if (c == null) {
      return;
    }
    final t = '${payload['t'] ?? ''}';
    final name = '${payload['nick'] ?? 'peer'}';
    final id = '${payload['id'] ?? ''}';
    if (channel == 'chat') {
      if (!c.admitted) {
        return;
      }
      if (t == 'chat') {
        _onChat(name, '${payload['text'] ?? ''}', '${payload['mid'] ?? ''}', id);
      } else if (t == 'typing') {
        setTyping(name, payload['on'] == true);
      }
      return;
    }
    if (t == 'claim') {
      final wasHost = c.isHost;
      if (!await c.takeClaim(payload)) {
        return;
      }
      if (wasHost && !c.isHost) {
        final handoff = await c.handoffPayload(id);
        if (handoff != null) {
          _signal(handoff);
        }
        _sys('$name took host with the master key');
      } else if (c.isHost) {
        _syncKey();
        _startHostBeacon();
        _sys('you hold this room');
      }
      notifyListeners();
      return;
    }
    if (t == 'host') {
      if (id == peerId) {
        return;
      }
      final yielded = c.onHost(payload);
      if (yielded) {
        _syncKey();
        _signal(c.askPayload(did: did));
        _sys('yielding host');
      }
      notifyListeners();
      return;
    }
    if (t == 'mode') {
      if (!c.isHost) {
        c.locked = '${payload['mode'] ?? 'open'}' == 'private';
        notifyListeners();
      }
      return;
    }
    if (t == 'ask') {
      Uint8List? pk;
      try {
        pk = fromHex('${payload['pk'] ?? ''}');
      } catch (_) {}
      if (pk == null || pk.length != 32) {
        return;
      }
      final member = Member(id, name, pk, did: '${payload['did'] ?? ''}');
      c.remember(id, name, pk, did: member.did);
      if (c.isHost && c.isMuted(id, name, pk, did: member.did)) {
        final left = c.muteLeft(id, name, pk, did: member.did);
        _signal({'t': 'deny', 'to': id, 'why': 'spam', 'sec': left});
        _sys('$name blocked for spam  ${left}s');
        return;
      }
      if (c.isHost && !c.locked && !c.kicked.contains(id)) {
        final admit = await c.autoAdmitPayload(member);
        if (admit != null) {
          _signal(admit);
        }
      } else if (c.isHost && c.locked) {
        _sys('$name waits at the door  /admit $name');
      }
      return;
    }
    if (t == 'admit' || t == 'rekey' || t == 'handoff') {
      if ('${payload['to'] ?? ''}' != peerId) {
        return;
      }
      final epoch = int.tryParse('${payload['epoch'] ?? 0}') ?? 0;
      if (await c.acceptKey('${payload['box'] ?? ''}', epoch)) {
        _syncKey();
        _sys(t == 'rekey' ? 'room key rotated' : 'in the room');
        notifyListeners();
      }
      return;
    }
    if (t == 'deny') {
      if ('${payload['to'] ?? ''}' == peerId) {
        if ('${payload['why'] ?? ''}' == 'spam') {
          _sys('host blocked you for spam  wait ${payload['sec'] ?? SpamWatch.banSec}s');
        } else {
          _sys('host kept you outside');
        }
      }
      return;
    }
    if (t == 'kick') {
      if ('${payload['to'] ?? ''}' != peerId) {
        return;
      }
      kicked = true;
      if ('${payload['why'] ?? ''}' == 'spam') {
        _sys('kicked for spam  wait ${payload['sec'] ?? SpamWatch.banSec}s before joining again');
      } else {
        _sys('kicked');
      }
      await stop();
      return;
    }
    if (t == 'hello' || t == 'nick') {
      try {
        c.remember(id, name, fromHex('${payload['pk'] ?? ''}'), did: '${payload['did'] ?? ''}');
      } catch (_) {}
      _sys('node=$name event=register region=wan');
    } else if (t == 'bye') {
      typists.remove(name);
      c.waiting.remove(id);
      c.members.remove(id);
      _sys('node=$name event=drain region=wan');
    }
  }

  Future<String> _bestLocalIp() async {
    try {
      final wifi = await NetworkInfo().getWifiIP();
      if (wifi != null && wifi.isNotEmpty && !wifi.startsWith('0.') && !wifi.contains(':')) {
        return wifi;
      }
    } catch (_) {}
    try {
      final ifaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in ifaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }
          return ip;
        }
      }
    } catch (_) {}
    return localIp;
  }

  Future<void> stop() async {
    running = false;
    _typingExpire?.cancel();
    _hostBeacon?.cancel();
    await _wan?.close();
    await _lan?.close();
    lines.clear();
    typists.clear();
    notifyListeners();
  }
}
