import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:speakeasy/speakeasy.dart';
import 'package:whetstone/storage/scene_client.dart';

void main() {
  test('posts the operation and summarises the result', () async {
    late http.Request seen;
    final HttpScene s = HttpScene(Uri.parse('http://x:1'), client: MockClient((http.Request r) async {
      seen = r;
      return http.Response(
          jsonEncode(<String, Object?>{
            'result': <String, Object?>{'created': <String>['Eye'], 'touched': <String>[]}
          }),
          200);
    }));
    expect(await s.operate(<String, Object?>{'op': 'create', 'shape': 'sphere'}), 'created Eye');
    expect(seen.url.path, '/blender/ops');
    expect(jsonDecode(seen.body), <String, Object?>{
      'ops': <Object?>[<String, Object?>{'op': 'create', 'shape': 'sphere'}]
    });
  });

  test('backend errors become script errors with the reason', () async {
    final HttpScene s = HttpScene(Uri.parse('http://x:1'), client: MockClient((http.Request r) async =>
        http.Response(jsonEncode(<String, Object?>{'detail': 'cannot reach Blender'}), 502)));
    await expectLater(s.operate(<String, Object?>{'op': 'render'}),
        throwsA(isA<ScriptError>().having((ScriptError e) => e.message, 'message', contains('cannot reach Blender'))));
  });

  test('summarize', () {
    expect(summarize(null), 'ok');
    expect(summarize(<String, Object?>{'deleted': <String>['a', 'b']}), 'deleted a, b');
  });
}
