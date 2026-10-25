import 'package:flutter/material.dart';

import 'pot_controller.dart';

/// Klassik serial monitor: gələn/gedən məlumat, əl ilə komanda və tez düymələr.
class TerminalPage extends StatefulWidget {
  final PotController pot;
  const TerminalPage({super.key, required this.pot});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _autoScroll = true;
  int _lastCount = 0;

  PotController get pot => widget.pot;

  static const _quick = [
    ('1', 'RFID'),
    ('2', 'Fan aç'),
    ('3', 'Fan dur'),
    ('6', 'Su aç'),
    ('7', 'Su dur'),
    ('4', 'Ləğv'),
    ('5', 'DHT'),
  ];

  @override
  void initState() {
    super.initState();
    pot.addListener(_onPot);
  }

  @override
  void dispose() {
    pot.removeListener(_onPot);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPot() {
    if (pot.log.length != _lastCount) {
      _lastCount = pot.log.length;
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    }
  }

  void _send() {
    final t = _input.text;
    if (t.isEmpty) return;
    pot.send(t);
    _input.clear();
  }

  String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      // alət paneli
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
        child: Row(children: [
          const Text('Sətir sonu:'),
          const SizedBox(width: 8),
          DropdownButton<LineEnding>(
            value: pot.lineEnding,
            underline: const SizedBox(),
            items: [
              for (final e in LineEnding.values) DropdownMenuItem(value: e, child: Text(e.label)),
            ],
            onChanged: (e) => pot.setLineEnding(e!),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Avtomatik sürüşdür',
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.pause),
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(tooltip: 'Təmizlə', icon: const Icon(Icons.delete_sweep), onPressed: pot.clearLog),
        ]),
      ),
      // log
      Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1A12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListenableBuilder(
            listenable: pot,
            builder: (_, _) => pot.log.isEmpty
                ? const Center(child: Text('Məlumat gözlənilir…', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: pot.log.length,
                    itemBuilder: (_, i) {
                      final l = pot.log[i];
                      final (Color c, String p) = switch (l.dir) {
                        LogDir.rx => (const Color(0xFF9CF6A8), '←'),
                        LogDir.tx => (const Color(0xFF8AC7FF), '→'),
                        LogDir.info => (Colors.white60, '•'),
                        LogDir.error => (const Color(0xFFFF8A80), '!'),
                      };
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: SelectableText.rich(
                          TextSpan(children: [
                            TextSpan(text: '${_time(l.time)} ', style: const TextStyle(color: Colors.white38)),
                            TextSpan(text: '$p ', style: TextStyle(color: c, fontWeight: FontWeight.bold)),
                            TextSpan(text: l.text, style: TextStyle(color: c)),
                          ]),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
      // tez düymələr
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            for (final (code, label) in _quick)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: cs.primary,
                    child: Text(code, style: TextStyle(fontSize: 11, color: cs.onPrimary)),
                  ),
                  label: Text(label),
                  onPressed: () => pot.send(code),
                ),
              ),
          ],
        ),
      ),
      // əl ilə yazma
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Komanda yazın…',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
          ]),
        ),
      ),
    ]);
  }
}
