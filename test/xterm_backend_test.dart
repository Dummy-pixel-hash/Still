import 'package:flutter_test/flutter_test.dart';
import 'package:still/src/terminal/xterm_backend.dart';

void main() {
  test('xterm backend feeds output and reports resize', () async {
    final backend = XtermBackend(cols: 80, rows: 24);
    expect(backend.cols, 80);

    // Plain text + SGR truecolor + unicode must not throw the parser.
    backend.feed('hello \x1b[38;2;255;100;0mtruecolor\x1b[0m ✓ 𐍈\n');

    final sizes = <String>[];
    final sub = backend.onResize.listen((s) => sizes.add('$s'));
    backend.resize(100, 30);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sizes, ['100x30']);

    await sub.cancel();
    backend.dispose();
  });
}
