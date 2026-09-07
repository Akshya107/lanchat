import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'crypto.dart';

typedef WanHandler = void Function(Map<String, dynamic> payload);

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

  String get topic => 'ec/v1/$room/m';

  Future<bool> connect() async {
    await close();
    // Cellular often blocks raw MQTT :1883. WebSocket URIs must include ws/wss.
    // Do not set secure=true together with useWebSocket — the client then
    // drops WebSocket and tries TLS TCP instead.
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
        client.subscribe(topic, MqttQos.atMostOnce);
        _client = client;
        connected = true;
        publish({'t': 'hello', 'id': peerId, 'nick': nick});
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
      final payload = openPayload(bytes, room);
      if (payload == null) {
        continue;
      }
      if ('${payload['id'] ?? ''}' == peerId) {
        continue;
      }
      onPayload(payload);
    }
  }

  void publish(Map<String, Object?> payload) {
    final client = _client;
    if (!connected || client == null) {
      return;
    }
    final body = Map<String, Object?>.from(payload);
    body.putIfAbsent('id', () => peerId);
    body.putIfAbsent('nick', () => nick);
    final builder = MqttClientPayloadBuilder();
    builder.addUTF8String(seal(body, room));
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!, retain: false);
  }

  Future<void> close() async {
    final client = _client;
    if (connected && client != null) {
      try {
        final body = {'t': 'bye', 'id': peerId, 'nick': nick};
        final builder = MqttClientPayloadBuilder();
        builder.addUTF8String(seal(body, room));
        client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!, retain: false);
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
