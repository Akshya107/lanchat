import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

import 'models/line.dart';
import 'net/crypto.dart';
import 'net/join.dart';
import 'net/lan.dart';
import 'net/logs.dart';
import 'net/wan.dart';

class ChatSession extends ChangeNotifier {
  ChatSession({required this.nick, this.roomHint = ''});

  String nick;
  final String roomHint;
  final peerId = newPeerId();
  late final String roomSeed = roomHint.length >= 4 ? normRoom(roomHint) : newRoomCode();
  String room = '';
  String localIp = '0.0.0.0';
  String transport = 'scan';
  int tcpPort = 0;
  bool muted = false;
  bool running = false;

  final lines = <TermLine>[];
  final typists = <String, DateTime>{};
  final _seen = <String>{};

  LanMesh? _lan;
  WanRoom? _wan;
  Timer? _typingExpire;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  bool _typingOn = false;

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
    return 'uplink  $localIp  path=$transport  room=$room  token=$token';
  }

  String get typingLabel {
    final now = DateTime.now();
    final names = typists.entries.where((e) => now.difference(e.value).inMilliseconds < 2400).map((e) => e.key).toList();
    if (names.isEmpty) {
      return '';
    }
    if (names.length == 1) {
      return '${names.first} is typing...';
    }
    return '${names.join(', ')} are typing...';
  }

  Future<void> start() async {
    running = true;
    room = roomSeed;
    await _detectPath();
    _lan = LanMesh(
      peerId: peerId,
      nick: nick,
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
      await Future<void>.delayed(const Duration(milliseconds: 110));
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

  void _onChat(String name, String text, String mid) {
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

  void setTyping(String name, bool on) {
    if (name.isEmpty) {
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
    _wan?.publish({'t': 'typing', 'on': on});
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
      _sys('slash: /join CODE  /room CODE  /code  /clear  /nick NAME  /mute  /quit');
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
      _lan?.broadcast({'t': 'nick', 'id': peerId, 'nick': nick});
      _wan?.publish({'t': 'nick'});
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
    final mid = newMessageId();
    _lan?.sendChat(text, mid);
    _wan?.publish({'t': 'chat', 'text': text, 'mid': mid});
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
    await _wan?.close();
    _wan = WanRoom(peerId: peerId, nick: nick, room: room, onPayload: _onWan);
    final ok = await _wan!.connect();
    if (ok) {
      _sys('room $room  internet on  ($transport)');
    } else {
      _wan = null;
      _sys('room offline  no internet / cell blocked mqtt?');
    }
  }

  void _onWan(Map<String, dynamic> payload) {
    final t = payload['t'];
    final name = '${payload['nick'] ?? 'peer'}';
    if (t == 'chat') {
      _onChat(name, '${payload['text'] ?? ''}', '${payload['mid'] ?? ''}');
    } else if (t == 'typing') {
      setTyping(name, payload['on'] == true);
    } else if (t == 'hello' || t == 'nick') {
      _sys('node=$name event=register region=wan');
    } else if (t == 'bye') {
      typists.remove(name);
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
    await _wan?.close();
    await _lan?.close();
    lines.clear();
    typists.clear();
    notifyListeners();
  }
}
