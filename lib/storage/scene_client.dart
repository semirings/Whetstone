/// Sends Speakeasy's 3D-scene commands (create, move, rotate, scale, delete,
/// render) to the Whetstone backend, which runs them in Blender.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:speakeasy/speakeasy.dart';

typedef SceneOperate = Future<String> Function(Map<String, Object?> op);

class HttpScene {
  HttpScene(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  /// Runs one operation. Returns a short summary; throws [ScriptError] with
  /// the reason when Blender can't be reached or refuses.
  Future<String> operate(Map<String, Object?> op) async {
    http.Response r;
    try {
      r = await _client
          .post(
            baseUrl.replace(path: '/blender/ops'),
            headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
            body: utf8.encode(jsonEncode(<String, Object?>{
              'ops': <Object?>[op],
            })),
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw ScriptError('cannot reach the Whetstone backend at $baseUrl ($e)');
    }
    final Object? data = jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode != 200) {
      final Object? detail = data is Map ? data['detail'] : null;
      throw ScriptError('${detail ?? 'backend said ${r.statusCode}'}');
    }
    return summarize(data is Map ? data['result'] : null);
  }
}

/// "created Eye", "moved Eye", ... from the backend's result dict.
String summarize(Object? result) {
  if (result is! Map) return 'ok';
  final List<String> parts = <String>[];
  void add(String verb, Object? names) {
    if (names is List && names.isNotEmpty) parts.add('$verb ${names.join(', ')}');
  }

  add('created', result['created']);
  add('changed', result['touched']);
  add('deleted', result['deleted']);
  add('rendered', result['rendered']);
  return parts.isEmpty ? 'ok' : parts.join('; ');
}
