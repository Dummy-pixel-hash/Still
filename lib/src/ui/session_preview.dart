import 'package:flutter/material.dart';

import '../session/still_session.dart';
import '../theme/still_theme.dart';

/// Static stylized preview inside a session card — the same role as the
/// prototype's TerminalPreview: a hint of what's inside, not live content.
/// Live output only ever appears in the fullscreen terminal.
class SessionPreview extends StatelessWidget {
  const SessionPreview({super.key, required this.session});

  final StillSession session;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: StillTheme.wellDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Stack(
        children: [
          DefaultTextStyle(
            style: StillTheme.mono.copyWith(fontSize: 10, height: 1.65),
            child: _body(),
          ),
          // Bottom fade, like the prototype's gradient mask.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 28,
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, StillTheme.previewWell],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (session.kind) {
      case SessionKind.editor:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('post.rs',
                style: TextStyle(color: Color(0xFFCECBD0))),
            const SizedBox(height: 6),
            _line('1', 'use crate::ledger::{Ledger, Tx};', accent: true),
            _line('2', ''),
            _line('3', 'pub fn settle(batch: &mut Batch) {', accent: true),
            _line('4', '    let ledger = Ledger::open()?;', accent: true),
            _line('5', '    for tx in batch.drain() {'),
            _line('6', '        ledger.post(Tx::from(tx))?;'),
            _line('7', '    }'),
            const Spacer(),
            const Text('NORMAL  feat/settle',
                style: TextStyle(color: Color(0xFFCDA3A3), fontSize: 9)),
          ],
        );
      case SessionKind.agent:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('✳ Claude Code',
                style: TextStyle(color: Color(0xFFE0DAD4))),
            SizedBox(height: 8),
            Text('● Reading src/ledger/post.rs'),
            Text('● Editing 3 files'),
            Text('+ 42  − 17   3 files',
                style: TextStyle(color: Color(0xFFA4B99A))),
            SizedBox(height: 6),
            Text('✳ Waiting for input ▍',
                style: TextStyle(color: Color(0xFFCFAD90))),
          ],
        );
      case SessionKind.git:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⑂ feat/idempotent-settle',
                style: TextStyle(color: Color(0xFFB6B0BD))),
            SizedBox(height: 8),
            Text('M post.rs',
                style: TextStyle(color: Color(0xFFB0BEA5))),
            Text('M retry.rs',
                style: TextStyle(color: Color(0xFFB0BEA5))),
            Text('a91f3c2 retry',
                style: TextStyle(color: Color(0xFFA69FBA))),
            Text('4be07d1 lock'),
            SizedBox(height: 6),
            Text('+ ledger.post(tx)?;',
                style: TextStyle(color: Color(0xFFA4B99A))),
            Text('- ledger.post(tx);',
                style: TextStyle(color: Color(0xFFC29595))),
          ],
        );
      case SessionKind.monitor:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('cpu ─────────────  34%',
                style: TextStyle(color: Color(0xFFA4B99A))),
            Text('▁▂▁▃▄▂▅▃▂▁▂▃▅▆▅▄▂▃▁▂▃▄▂▁',
                style: TextStyle(color: Color(0xFF9EAA95))),
            Text('mem ▰▰▰▰▰▰▰▱▱▱▱  61%'),
            SizedBox(height: 6),
            Text('qemu-system   12.4  4.2G'),
            Text('zfs-arc        6.1  880M'),
          ],
        );
      case SessionKind.logs:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 7; i++)
              Row(
                children: [
                  Text('14:32:0$i  ',
                      style: StillTheme.mono.copyWith(
                          fontSize: 10,
                          height: 1.65,
                          color: const Color(0xFF79737F))),
                  Text(i == 3 ? '202' : '200',
                      style: StillTheme.mono.copyWith(
                          fontSize: 10,
                          height: 1.65,
                          color: const Color(0xFFA4B99A))),
                  Text(
                      '  ${['POST /settle', 'GET /ledger', 'GET /health'][i % 3]}',
                      style: StillTheme.mono
                          .copyWith(fontSize: 10, height: 1.65)),
                ],
              ),
          ],
        );
      case SessionKind.shell:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last login: ${session.host}',
                style: StillTheme.mono.copyWith(
                    fontSize: 10, height: 1.65, color: const Color(0xFF78727F))),
            const SizedBox(height: 6),
            Text('\$ zpool status tank',
                style: StillTheme.mono.copyWith(
                    fontSize: 10, height: 1.65, color: const Color(0xFFC6C0CC))),
            Text('  state: ONLINE',
                style:
                    StillTheme.mono.copyWith(fontSize: 10, height: 1.65)),
            const SizedBox(height: 8),
            Text('❯ ▍',
                style: StillTheme.mono.copyWith(
                    fontSize: 10, height: 1.65, color: const Color(0xFFBCB5C5))),
          ],
        );
    }
  }

  Widget _line(String no, String text, {bool accent = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(no,
              style: StillTheme.mono.copyWith(
                  fontSize: 10,
                  height: 1.65,
                  color: const Color(0xFF66626B))),
        ),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: StillTheme.mono.copyWith(
                  fontSize: 10,
                  height: 1.65,
                  color: accent
                      ? const Color(0xFFCDA3A3)
                      : const Color(0xFFA9A6AF))),
        ),
      ],
    );
  }
}
