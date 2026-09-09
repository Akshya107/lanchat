import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hud.dart';
import 'models/line.dart';
import 'session.dart';
import 'theme.dart';

class GatePage extends StatefulWidget {
  const GatePage({super.key});

  @override
  State<GatePage> createState() => _GatePageState();
}

class _GatePageState extends State<GatePage> {
  final _name = TextEditingController();
  final _room = TextEditingController();
  final _master = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _room.dispose();
    _master.dispose();
    super.dispose();
  }

  void _enter() {
    var nick = _name.text.trim();
    var room = _room.text.trim();
    final asCommand = RegExp(r'^/?room\s+([A-Za-z0-9\-]+)$', caseSensitive: false).firstMatch(nick);
    if (asCommand != null) {
      room = asCommand.group(1) ?? room;
      nick = 'operator';
    }
    if (nick.toLowerCase().startsWith('/room')) {
      nick = 'operator';
    }
    if (nick.isEmpty) {
      nick = 'operator';
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SessionPage(nick: nick, roomHint: room, masterKeyHex: _master.text.trim()),
      ),
    );
  }

  InputDecoration _field({required String hint, required double size}) {
    return InputDecoration(
      prefixText: '▸ ',
      prefixStyle: mono(color: gridCyan, size: size, weight: FontWeight.bold),
      hintText: hint,
      hintStyle: mono(color: gridDim, size: size),
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF004433))),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: gridCyan)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: gridBlack,
      body: FuturisticShell(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const HudBar(left: '◈  LANCHAT  ▸  CHRONO-MESH', right: 'NODE STANDBY'),
                const SizedBox(height: 18),
                Text('░▒▓█  CHRONO GATE  █▓▒░', style: mono(color: gridCyan, size: 20, weight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('PHOTONIC UPLINK  ·  IDENTITY VECTOR REQUIRED', style: mono(color: gridDim, size: 11)),
                const SizedBox(height: 22),
                HudFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('IDENTIFY OPERATOR', style: mono(color: gridCyan, size: 12, weight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        autofocus: true,
                        cursorColor: gridCyan,
                        style: mono(size: 18, weight: FontWeight.bold),
                        decoration: _field(hint: 'ADA', size: 18),
                        inputFormatters: [LengthLimitingTextInputFormatter(24)],
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 20),
                      Text('ROOM CODE FROM COMPUTER', style: mono(color: gridCyan, size: 12, weight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _room,
                        cursorColor: gridCyan,
                        textCapitalization: TextCapitalization.characters,
                        style: mono(size: 18, weight: FontWeight.bold),
                        decoration: _field(hint: 'B66LMJ', size: 18),
                        inputFormatters: [LengthLimitingTextInputFormatter(12)],
                        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      ),
                      const SizedBox(height: 20),
                      Text('MASTER KEY (OPTIONAL)', style: mono(color: gridCyan, size: 12, weight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _master,
                        cursorColor: gridCyan,
                        obscureText: true,
                        style: mono(size: 16, weight: FontWeight.bold),
                        decoration: _field(hint: 'paste to take host', size: 16),
                        inputFormatters: [LengthLimitingTextInputFormatter(80)],
                        onSubmitted: (_) => _enter(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Name = who you are.\n'
                  'Room = the code on the computer (room=XXXXXX).\n'
                  'Leave room blank to create a new one.\n'
                  'Master key = only you. Takes host in any room.',
                  style: mono(color: gridDim, size: 12),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: gridBlack,
                      backgroundColor: gridCyan,
                      side: const BorderSide(color: gridCyan),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _enter,
                    child: Text('OPEN LATTICE', style: mono(color: gridBlack, size: 16, weight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.nick, this.roomHint = '', this.masterKeyHex = ''});

  final String nick;
  final String roomHint;
  final String masterKeyHex;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  late final ChatSession session;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    session = ChatSession(nick: widget.nick, roomHint: widget.roomHint, masterKeyHex: widget.masterKeyHex)..addListener(_onTick);
    session.start();
  }

  void _onTick() {
    if (!session.running && mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const GatePage()));
      return;
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    session
      ..removeListener(_onTick)
      ..stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text;
    _input.clear();
    session.localTyping(false);
    session.submit(text);
  }

  Future<void> _backToGate() async {
    await session.stop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _backToGate();
        }
      },
      child: Scaffold(
      backgroundColor: gridBlack,
      body: FuturisticShell(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: HudBar(
                  left: '◈  LANCHAT  ▸  CHRONO-MESH',
                  right: 'NODE LIVE',
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 10, 2),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _backToGate,
                      child: Text('◂ COLLAPSE', style: mono(color: gridCyan, size: 13, weight: FontWeight.bold)),
                    ),
                    Expanded(
                      child: Text(
                        'PHOTONIC SESSION',
                        textAlign: TextAlign.right,
                        style: mono(color: gridDim, size: 11),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: session.waitingOutside
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: HudFrame(
                            child: Text(
                              'WAITING OUTSIDE\n\nhost has not let you in\nshare your name so they can /admit you',
                              textAlign: TextAlign.center,
                              style: mono(size: 14, weight: FontWeight.bold),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        itemCount: session.lines.length,
                        itemBuilder: (context, i) => _LineView(line: session.lines[i]),
                      ),
              ),
              Container(
                width: double.infinity,
                color: const Color(0xFF001A14),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(session.status, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono(color: gridCyan, size: 11)),
              ),
              SizedBox(
                width: double.infinity,
                height: 22,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(session.typingLabel, style: mono(color: gridSoft, size: 12, style: FontStyle.italic)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        cursorColor: gridCyan,
                        style: mono(size: 15),
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          isDense: true,
                          prefixText: '▸ ',
                          prefixStyle: mono(color: gridCyan, size: 15, weight: FontWeight.bold),
                          hintText: 'transmit across the lattice…',
                          hintStyle: mono(color: gridDim, size: 15),
                          border: InputBorder.none,
                        ),
                        onChanged: (v) => session.localTyping(v.trim().isNotEmpty && !v.trimLeft().startsWith('/')),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    TextButton(
                      onPressed: _send,
                      child: Text('SEND', style: mono(color: gridCyan, size: 13, weight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _LineView extends StatelessWidget {
  const _LineView({required this.line});

  final TermLine line;

  @override
  Widget build(BuildContext context) {
    if (line.kind == LineKind.chat) {
      return _SciFiBubble(line: line);
    }
    if (line.kind == LineKind.log || line.kind == LineKind.warn) {
      return const SizedBox.shrink();
    }
    final color = switch (line.kind) {
      LineKind.hello => gridBlack,
      LineKind.boot => gridSoft,
      LineKind.sys => gridDim,
      _ => gridDim,
    };
    final bg = line.kind == LineKind.hello ? gridCyan : Colors.transparent;
    return ColoredBox(
      color: bg,
      child: Text(
        line.text.isEmpty ? ' ' : line.text,
        textAlign: line.kind == LineKind.sys ? TextAlign.center : TextAlign.left,
        style: mono(color: line.kind == LineKind.hello ? gridBlack : color, size: 12.5, weight: line.kind == LineKind.boot || line.kind == LineKind.hello ? FontWeight.bold : FontWeight.w500),
      ),
    );
  }
}

class _SciFiBubble extends StatelessWidget {
  const _SciFiBubble({required this.line});

  final TermLine line;

  @override
  Widget build(BuildContext context) {
    final mine = line.mine;
    final accent = mine ? gridGreen : gridCyan;
    final when = line.at;
    final stamp =
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}:${when.second.toString().padLeft(2, '0')}';
    final tag = mine ? 'TX // ${line.nick.toUpperCase()}' : 'RX // ${line.nick.toUpperCase()}';

    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: CustomPaint(
            painter: HudShapePainter(color: accent, fill: mine),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(mine ? '▸' : '◂', style: mono(color: mine ? gridBlack : accent, size: 11, weight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Text(tag, style: mono(color: mine ? gridBlack : accent, size: 10, weight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(line.text, style: mono(color: mine ? gridBlack : gridSoft, size: 14, weight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(stamp, style: mono(color: mine ? const Color(0xFF003300) : gridDim, size: 10)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
