import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _enter() {
    final nick = _name.text.trim().isEmpty ? 'operator' : _name.text.trim();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => SessionPage(nick: nick)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: gridBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('░▒▓█  LANCHAT  █▓▒░', style: mono(size: 22, weight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('NEURAL GATE', style: mono(color: gridDim)),
              const SizedBox(height: 32),
              Text('> IDENTIFY OPERATOR', style: mono()),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                autofocus: true,
                cursorColor: gridGreen,
                style: mono(size: 18, weight: FontWeight.bold),
                decoration: InputDecoration(
                  prefixText: '\$ ',
                  prefixStyle: mono(size: 18, weight: FontWeight.bold),
                  hintText: 'ADA',
                  hintStyle: mono(color: gridDim, size: 18),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: gridDim)),
                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: gridGreen)),
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(24)],
                onSubmitted: (_) => _enter(),
              ),
              const SizedBox(height: 28),
              Text(
                'wifi / hotspot  →  local mesh, no internet\n'
                'mobile data     →  room code, any city',
                style: mono(color: gridDim, size: 12),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: gridBlack,
                    backgroundColor: gridGreen,
                    side: const BorderSide(color: gridGreen),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _enter,
                  child: Text('OPEN UPLINK', style: mono(color: gridBlack, size: 16, weight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.nick});

  final String nick;

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
    session = ChatSession(nick: widget.nick)..addListener(_onTick);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: gridBlack,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                itemCount: session.lines.length,
                itemBuilder: (context, i) => _LineView(line: session.lines[i]),
              ),
            ),
            Container(
              width: double.infinity,
              color: const Color(0xFF001A00),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(session.status, maxLines: 2, overflow: TextOverflow.ellipsis, style: mono(color: gridMid, size: 11)),
            ),
            SizedBox(
              width: double.infinity,
              height: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
                      cursorColor: gridGreen,
                      style: mono(size: 15),
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '\$ ',
                        prefixStyle: mono(size: 15, weight: FontWeight.bold),
                        hintText: 'transmit…',
                        hintStyle: mono(color: gridDim, size: 15),
                        border: InputBorder.none,
                      ),
                      onChanged: (v) => session.localTyping(v.trim().isNotEmpty && !v.trimLeft().startsWith('/')),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  TextButton(
                    onPressed: _send,
                    child: Text('SEND', style: mono(size: 13, weight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
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
    final bg = line.kind == LineKind.hello ? gridGreen : gridBlack;
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
            painter: _HudPainter(color: accent, fill: mine),
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

class _HudPainter extends CustomPainter {
  _HudPainter({required this.color, required this.fill});

  final Color color;
  final bool fill;

  @override
  void paint(Canvas canvas, Size size) {
    const cut = 10.0;
    final path = Path()
      ..moveTo(cut, 0)
      ..lineTo(size.width - cut, 0)
      ..lineTo(size.width, cut)
      ..lineTo(size.width, size.height - cut)
      ..lineTo(size.width - cut, size.height)
      ..lineTo(cut, size.height)
      ..lineTo(0, size.height - cut)
      ..lineTo(0, cut)
      ..close();

    if (fill) {
      canvas.drawPath(path, Paint()..color = color);
    } else {
      canvas.drawPath(path, Paint()..color = gridPanel);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.12)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final tick = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.drawLine(const Offset(cut, 0), const Offset(cut + 16, 0), tick);
    canvas.drawLine(Offset(size.width - cut - 16, size.height), Offset(size.width - cut, size.height), tick);
  }

  @override
  bool shouldRepaint(covariant _HudPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.fill != fill;
  }
}
