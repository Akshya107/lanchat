import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'crypto.dart';

typedef WanHandler = void Function(Map<String, dynamic> payload, String channel);

class WanRoom {
  WanRoom({
    required this.peerId,
    required this.nick,
    required String room,
    required this.onPayload,
  }) : room = normRoom(room);

  final String peerId;
  String nick;
  String room;
  final WanHandler onPayload;

  MqttServerClient? _client;
  bool connected = false;
  Uint8List? roomKey;

  String get signalTopic => 'ec/v2/$room/s';
  String get chatTopic => 'ec/v2/$room/m';

  void setRoomKey(Uint8List? key) {
    roomKey = key;
  }

  Future<bool> connect() async {
    await close();
    final attempts = <({String host, int port, bool ws})>[
      (host: 'wss://broker.hivemq.com/mqtt', port: 8884, ws: true),
      (host: 'ws://broker.hivemq.com/mqtt', port: 8000, ws: true),
      (host: 'wss://test.mosquitto.org/mqtt', port: 8081, ws: true),
      (host: 'broker.hivemq.com', port: 1883, ws: false),
      (host: 'test.mosquitto.org', port: 1883, ws: false),
    ];
    for (final a in attempts) {
      final id = 'ec${peerId.substring(0, 16)}';
      final client = MqttServerClient.withPort(a.host, id, a.port)
        ..keepAlivePeriod = 30
        ..autoReconnect = true
        ..logging(on: false)
        ..useWebSocket = a.ws
        ..setProtocolV311();
      if (a.ws) {
        client.websocketProtocols = ['mqtt'];
      }
      try {
        await client.connect().timeout(const Duration(seconds: 6));
        if (client.connectionStatus?.state != MqttConnectionState.connected) {
          client.disconnect();
          continue;
        }
        client.updates?.listen(_onMessage);
        client.subscribe(signalTopic, MqttQos.atMostOnce);
        client.subscribe(chatTopic, MqttQos.atMostOnce);
        _client = client;
        connected = true;
        return true;
      } catch (_) {
        try {
          client.disconnect();
        } catch (_) {}
      }
    }
    return false;
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final rec = event.payload;
      if (rec is! MqttPublishMessage) {
        continue;
      }
      final bytes = rec.payload.message;
      final topic = event.topic;
      final channel = topic.endsWith('/m') ? 'chat' : 'signal';
      unawaited(_dispatch(bytes, channel));
    }
  }

  Future<void> _dispatch(List<int> bytes, String channel) async {
    Map<String, dynamic>? payload;
    if (channel == 'chat') {
      final key = roomKey;
      if (key == null) {
        return;
      }
      payload = await openChat(bytes, room, key);
    } else {
      try {
        final obj = jsonDecode(utf8.decode(bytes));
        if (obj is Map<String, dynamic>) {
          payload = obj;
        }
      } catch (_) {}
    }
    if (payload == null) {
      return;
    }
    if ('${payload['id'] ?? ''}' == peerId && payload['t'] != 'claim') {
      return;
    }
    onPayload(payload, channel);
  }

  void publishSignal(Map<String, Object?> payload) {
    final client = _client;
    if (!connected || client == null) {
      return;
    }
    final body = Map<String, Object?>.from(payload);
    body.putIfAbsent('id', () => peerId);
    body.putIfAbsent('nick', () => nick);
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(jsonEncode(body));
    client.publishMessage(signalTopic, MqttQos.atMostOnce, builder.payload!, retain: false);
  }

  Future<void> publishChat(Map<String, Object?> payload) async {
    final client = _client;
    final key = roomKey;
    if (!connected || client == null || key == null) {
      return;
    }
    final body = Map<String, Object?>.from(payload);
    body.putIfAbsent('id', () => peerId);
    body.putIfAbsent('nick', () => nick);
    final blob = await sealChat(body, room, key);
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(blob);
    client.publishMessage(chatTopic, MqttQos.atMostOnce, builder.payload!, retain: false);
  }

  Future<void> close() async {
    final client = _client;
    if (connected && client != null) {
      try {
        final builder = MqttClientPayloadBuilder();
        builder.addUTF8String(jsonEncode({'t': 'bye', 'id': peerId, 'nick': nick}));
        client.publishMessage(signalTopic, MqttQos.atMostOnce, builder.payload!, retain: false);
      } catch (_) {}
    }
    connected = false;
    _client = null;
    if (client == null) {
      return;
    }
    try {
      client.disconnect();
    } catch (_) {}
  }
}
