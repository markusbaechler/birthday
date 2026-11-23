import 'package:flutter_test/flutter_test.dart';
import 'package:geburtstage/data/database.dart';
import 'package:geburtstage/data/style_profile.dart';

Greeting _g(int id, String sent, String variants) => Greeting(
      id: id,
      personId: id,
      year: 2026,
      sentText: sent,
      channel: Channels.whatsapp,
      status: GreetingStatus.sent,
      createdAt: DateTime(2026, 1, id),
      variants: variants,
    );

void main() {
  const v =
      '[{"title":"a","text":"Liebe Silvia, zum 44. wünsche ich dir einen wunderbaren Tag am Bodensee."}]';

  test('unchanged AI text teaches nothing', () {
    final l = StyleProfile.learn([
      _g(1, 'Liebe Silvia, zum 44. wünsche ich dir einen wunderbaren  Tag am Bodensee.', v)
    ]);
    expect(l.examples, isEmpty);
    expect(l.edits, isEmpty);
  });

  test('an edited draft becomes example and correction', () {
    final l = StyleProfile.learn(
        [_g(1, 'Sili, zum 44. einen wunderbaren Tag am Bodensee. Häbs guet!', v)]);
    expect(l.examples, hasLength(1));
    expect(l.edits, hasLength(1));
  });

  test('an own text is an example without correction', () {
    final l = StyleProfile.learn([_g(1, 'Alte Hütte, lass dich feiern und trink eins auf mich.', v)]);
    expect(l.examples, hasLength(1));
    expect(l.edits, isEmpty);
  });

  test('prompt block only when there is something', () {
    expect(const StyleProfile().toPrompt(), '');
    expect(const StyleProfile(note: 'kurz, per Du').toPrompt(), contains('kurz, per Du'));
  });
}
