import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:still/src/config/ssh_config.dart';
import 'package:still/src/session/remote_session_controller.dart';
import 'package:still/src/ssh/ssh_connection.dart';
import 'package:still/src/terminal/terminal_backend.dart';

class FakeTerminal implements TerminalBackend {
  final fed = <String>[];
  final out = StreamController<String>.broadcast();
  final resizes = StreamController<TerminalSize>.broadcast();
  @override
  int cols = 80;
  @override
  int rows = 24;

  @override
  void feed(String data) => fed.add(data);

  @override
  Stream<String> get output => out.stream;

  @override
  Stream<TerminalSize> get onResize => resizes.stream;

  @override
  void resize(int c, int r) {
    cols = c;
    rows = r;
  }

  @override
  void dispose() {
    out.close();
    resizes.close();
  }
}

class FakeChannel implements SshShellChannel {
  final written = <String>[];
  final stdoutCtrl = StreamController<Uint8List>.broadcast();
  final doneCtrl = Completer<void>();
  int lastCols = 0;
  int lastRows = 0;
  int openCount = 0;

  @override
  Stream<Uint8List> get stdout => stdoutCtrl.stream;

  @override
  void write(Uint8List data) =>
      written.add(String.fromCharCodes(data));

  @override
  void resize(int cols, int rows,
      [int pixelWidth = 0, int pixelHeight = 0]) {
    lastCols = cols;
    lastRows = rows;
  }

  @override
  Future<void> get done => doneCtrl.future;

  @override
  Future<void> close() async {
    await stdoutCtrl.close();
  }
}

class FakeFactory implements SshConnectionFactory {
  final List<FakeChannel> channels = [];
  @override
  Future<SshShellChannel> openShell(SshConfig config) async {
    final c = FakeChannel()..openCount = channels.length + 1;
    channels.add(c);
    return c;
  }
}

SshConfig testConfig() => const SshConfig(
      host: 'example',
      username: 'u',
      tmuxSession: 'still',
    );

void main() {
  test('connect attaches tmux and bridges remote->terminal', () async {
    final term = FakeTerminal();
    final factory = FakeFactory();
    final ctrl =
        RemoteSessionController(terminal: term, sshFactory: factory);

    await ctrl.connect(testConfig());
    expect(ctrl.current, RemoteSessionStatus.live);
    expect(factory.channels.length, 1);
    expect(factory.channels.first.written.join(),
        contains('tmux -u new-session -A -s still'));

    // Remote bytes land in the emulator.
    factory.channels.first.stdoutCtrl.add(Uint8List.fromList([104, 105]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(term.fed.join(), 'hi');

    // User input flows to the remote.
    term.out.add('ls\n');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(factory.channels.first.written.join(), contains('ls\n'));

    await ctrl.disconnect();
    term.dispose();
  });

  test('reconnect opens a fresh channel to the same tmux session',
      () async {
    final term = FakeTerminal();
    final factory = FakeFactory();
    final ctrl =
        RemoteSessionController(terminal: term, sshFactory: factory);

    await ctrl.connect(testConfig());
    await ctrl.reconnect();
    expect(factory.channels.length, 2);
    expect(factory.channels[1].written.join(),
        contains('tmux -u new-session -A -s still'));

    await ctrl.disconnect();
    term.dispose();
  });

  test('terminal resize forwards SSH window-change', () async {
    final term = FakeTerminal();
    final factory = FakeFactory();
    final ctrl =
        RemoteSessionController(terminal: term, sshFactory: factory);

    await ctrl.connect(testConfig());
    term.resizes.add(const TerminalSize(120, 40));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(factory.channels.first.lastCols, 120);
    expect(factory.channels.first.lastRows, 40);

    await ctrl.disconnect();
    term.dispose();
  });
}
