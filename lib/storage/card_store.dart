/// Where cards are kept. The app talks to this interface; the real
/// implementation is the Whetstone backend over HTTP (port 8402).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/model.dart';
import 'card_codec.dart';

class StoreException implements Exception {
  StoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A card and the name of the stack it belongs to.
class StoredCard {
  const StoredCard(this.card, this.stack);
  final RecipeCard card;
  final String stack;
}

abstract class CardStore {
  Future<List<StoredCard>> loadAll();
  Future<void> save(RecipeCard card);
  Future<void> delete(String id);
}

class HttpCardStore implements CardStore {
  HttpCardStore(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  Uri _uri(String path) => baseUrl.replace(path: path);

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 10));
    } catch (e) {
      throw StoreException('cannot reach the Whetstone backend at $baseUrl ($e)');
    }
  }

  @override
  Future<List<StoredCard>> loadAll() async {
    final http.Response r = await _send(() => _client.get(_uri('/cards')));
    if (r.statusCode != 200) {
      throw StoreException('backend said ${r.statusCode} when loading cards');
    }
    final Object? data = jsonDecode(utf8.decode(r.bodyBytes));
    final Object? list = data is Map ? data['cards'] : null;
    if (list is! List) throw StoreException('backend sent something unexpected');
    return <StoredCard>[
      for (final Object? c in list)
        if (c is Map<String, Object?>) StoredCard(cardFromJson(c), stackNameOf(c))
    ];
  }

  @override
  Future<void> save(RecipeCard card) async {
    final String id = Uri.encodeComponent(card.id);
    final http.Response r = await _send(() => _client.put(
          _uri('/cards/$id'),
          headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
          body: utf8.encode(jsonEncode(cardToJson(card))),
        ));
    if (r.statusCode != 200) {
      throw StoreException('backend said ${r.statusCode} when saving "${card.name}"');
    }
  }

  @override
  Future<void> delete(String id) async {
    final http.Response r =
        await _send(() => _client.delete(_uri('/cards/${Uri.encodeComponent(id)}')));
    if (r.statusCode != 204 && r.statusCode != 404) {
      throw StoreException('backend said ${r.statusCode} when deleting a card');
    }
  }
}

/// Keeps cards in memory. For tests and for running without a backend.
class MemoryCardStore implements CardStore {
  final Map<String, Map<String, Object?>> saved = <String, Map<String, Object?>>{};
  Object? failWith;

  @override
  Future<List<StoredCard>> loadAll() async => <StoredCard>[
        for (final Map<String, Object?> j in saved.values)
          StoredCard(cardFromJson(j), stackNameOf(j))
      ];

  @override
  Future<void> save(RecipeCard card) async {
    if (failWith != null) throw StoreException('$failWith');
    saved[card.id] = cardToJson(card);
  }

  @override
  Future<void> delete(String id) async {
    if (failWith != null) throw StoreException('$failWith');
    saved.remove(id);
  }
}
