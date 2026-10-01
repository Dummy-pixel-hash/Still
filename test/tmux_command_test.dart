import 'package:flutter_test/flutter_test.dart';
import 'package:still/src/tmux/tmux.dart';

void main() {
  test('attach command uses -A with explicit size', () {
    const plan = TmuxPlan(sessionName: 'still');
    expect(plan.attachCommand(cols: 80, rows: 24),
        'tmux -u new-session -A -s still -x 80 -y 24\n');
  });

  test('session names are sanitized against shell injection', () {
    expect(TmuxPlan.sanitizeName('still; rm -rf /'), 'still__rm_-rf__');
    expect(TmuxPlan.sanitizeName(''), 'still');
    expect(TmuxPlan.sanitizeName('dev-1.2_ok'), 'dev-1.2_ok');
  });

  test('reconnect reuses same attach command (persistence)', () {
    const plan = TmuxPlan(sessionName: 'still');
    final first = plan.attachCommand(cols: 100, rows: 30);
    final second = plan.attachCommand(cols: 100, rows: 30);
    expect(first, second);
    expect(first, contains('new-session -A -s still'));
  });
}
