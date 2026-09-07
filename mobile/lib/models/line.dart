enum LineKind { log, warn, boot, hello, chat, sys }

class TermLine {
  TermLine(this.kind, this.text, {this.nick = '', this.mine = false, DateTime? at}) : at = at ?? DateTime.now();

  final LineKind kind;
  final String text;
  final String nick;
  final bool mine;
  final DateTime at;
}
