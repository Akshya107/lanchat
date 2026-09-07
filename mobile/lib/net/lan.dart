import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef LanChat = void Function(String nick, String text, String mid);
typedef LanPeer = void Function(String id, String nick);
typedef LanTyping = void Function(String nick, bool on);

class LanMesh {
  LanMesh({
    required this.peerId,
    required this.nick,
    required this.onChat,
    required this.onJoin,
    required this.onLeave,
    required this.onTyping,
  });

  final String peerId;
  String nick;
  final LanChat onChat;
  final LanPeer onJoin;
  final LanPeer onLeave;
  final LanTyping onTyping;

  ServerSocket? _server;
  RawDatagramSocket? _beacon;
  Timer? _announce;
  int tcpPort = 0;
  final _peers = <String, Socket>{};
  final _nicks = <String, String>{};
  final _pending = <String>{};

  static const beaconPort = 48721;

  Future<int> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    tcpPort = _server!.port;
    _server!.listen(_onInbound);
    try {
      _beacon = await RawDatagramSocket.bind(InternetAddress.anyIPv4, beaconPort);
      _beacon!
        ..broadcastEnabled = true
        ..listen((event) {
          if (event == RawSocketEvent.read) {
            final dg = _beacon?.receive();
            if (dg != null) {
              _onBeacon(dg);
            }
          }
        });
      _announce = Timer.periodic(const Duration(milliseconds: 1200), (_) => _broadcastBeacon());
      _broadcastBeacon();
    } catch (_) {
      // Cellular / restricted Wi-Fi may block UDP bind. WAN still works.
    }
    return tcpPort;
  }

  Uint8List _packBeacon() {
    final pid = _hexBytes(peerId.padRight(32, '0').substring(0, 32));
    final name = utf8.encode(nick).toList();
    while (name.length < 24) {
      name.add(0);
    }
    final out = BytesBuilder();
    out.add(ascii.encode('EC01'));
    out.add(pid);
    out.add(name.take(24).toList());
    out.addByte((tcpPort >> 8) & 0xFF);
    out.addByte(tcpPort & 0xFF);
    return out.toBytes();
  }

  List<int> _hexBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  void _broadcastBeacon() {
    final sock = _beacon;
    if (sock == null || tcpPort == 0) {
      return;
    }
    final payload = _packBeacon();
    try {
      sock.send(payload, InternetAddress('255.255.255.255'), beaconPort);
    } catch (_) {}
  }

  void _onBeacon(Datagram dg) {
    final data = dg.data;
    if (data.length < 4 + 16 + 24 + 2) {
      return;
    }
    if (ascii.decode(data.sublist(0, 4)) != 'EC01') {
      return;
    }
    final id = data.sublist(4, 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (id == peerId) {
      return;
    }
    final nameBytes = data.sublist(20, 44);
    final zero = nameBytes.indexOf(0);
    final name = utf8.decode(zero < 0 ? nameBytes : nameBytes.sublist(0, zero), allowMalformed: true);
    final port = (data[44] << 8) | data[45];
    final host = dg.address.address;
    if (host.startsWith('127.')) {
      return;
    }
    unawaited(connect(id, name.isEmpty ? 'peer' : name, host, port));
  }

  Future<void> _onInbound(Socket socket) async {
    await _session(socket);
  }

  Future<void> connect(String id, String name, String host, int port) async {
    if (id == peerId || _peers.containsKey(id) || _pending.contains(id)) {
      return;
    }
    _pending.add(id);
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
      await _session(socket);
    } catch (_) {
    } finally {
      _pending.remove(id);
    }
  }

  Future<bool> connectHost(String host, int port) async {
    final marker = 'addr:$host:$port';
    if (_pending.contains(marker)) {
      return false;
    }
    _pending.add(marker);
    final before = Set<String>.from(_peers.keys);
    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      unawaited(_session(socket));
      for (var i = 0; i < 25; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_peers.keys.any((k) => !before.contains(k))) {
          return true;
        }
      }
    } catch (_) {
      return false;
    } finally {
      _pending.remove(marker);
    }
    return _peers.keys.any((k) => !before.contains(k));
  }

  Future<void> _session(Socket socket) async {
    String? peerId;
    String nick = 'peer';
    final buf = StringBuffer();
    try {
      _write(socket, {'t': 'hello', 'id': this.peerId, 'nick': this.nick});
      await for (final chunk in socket) {
        buf.write(utf8.decode(chunk, allowMalformed: true));
        while (true) {
          final all = buf.toString();
          final nl = all.indexOf('\n');
          if (nl < 0) {
            break;
          }
          final line = all.substring(0, nl);
          buf
            ..clear()
            ..write(all.substring(nl + 1));
          Map<String, dynamic>? msg;
          try {
            msg = jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final t = msg['t'];
          if (peerId == null) {
            if (t != 'hello') {
              return;
            }
            peerId = '${msg['id'] ?? ''}';
            nick = '${msg['nick'] ?? 'peer'}';
            if (peerId.isEmpty || peerId == this.peerId || _peers.containsKey(peerId)) {
              return;
            }
            _peers[peerId] = socket;
            _nicks[peerId] = nick;
            onJoin(peerId, nick);
            continue;
          }
          if (t == 'chat') {
            final text = '${msg['text'] ?? ''}';
            if (text.isNotEmpty) {
              nick = '${msg['nick'] ?? nick}';
              onChat(nick, text, '${msg['mid'] ?? ''}');
            }
          } else if (t == 'nick') {
            nick = '${msg['nick'] ?? nick}';
            _nicks[peerId] = nick;
          } else if (t == 'typing') {
            onTyping('${msg['nick'] ?? nick}', msg['on'] == true);
          }
        }
      }
    } catch (_) {
    } finally {
      final id = peerId;
      if (id != null) {
        _peers.remove(id);
        final left = _nicks.remove(id) ?? nick;
        onLeave(id, left);
      }
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  void _write(Socket socket, Map<String, Object?> payload) {
    socket.add(utf8.encode('${jsonEncode(payload)}\n'));
  }

  void broadcast(Map<String, Object?> payload) {
    final blob = utf8.encode('${jsonEncode(payload)}\n');
    for (final socket in List<Socket>.from(_peers.values)) {
      try {
        socket.add(blob);
      } catch (_) {}
    }
  }

  void sendChat(String text, String mid) {
    broadcast({'t': 'chat', 'id': peerId, 'nick': nick, 'text': text, 'mid': mid});
  }

  void sendTyping(bool on) {
    broadcast({'t': 'typing', 'id': peerId, 'nick': nick, 'on': on});
  }

  Future<void> close() async {
    _announce?.cancel();
    _announce = null;
    try {
      _beacon?.close();
    } catch (_) {}
    _beacon = null;
    for (final socket in List<Socket>.from(_peers.values)) {
      try {
        socket.destroy();
      } catch (_) {}
    }
    _peers.clear();
    _nicks.clear();
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
  }
}
