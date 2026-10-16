import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A reader of a server-sent events stream, line by line.
final class EventClient {
  EventClient._(this._client, this.response, this._lines);

  /// Connects to [url] and waits for the response head.
  static Future<EventClient> connect(Uri url) async {
    final client = HttpClient();
    final response = await (await client.getUrl(url)).close();
    final lines = StreamIterator(
      response.transform(utf8.decoder).transform(const LineSplitter()),
    );
    return EventClient._(client, response, lines);
  }

  static const _wait = Duration(seconds: 30);

  final HttpClient _client;
  final StreamIterator<String> _lines;

  /// The response head.
  final HttpClientResponse response;

  /// The name of the next event, or `null` when the stream ends first.
  Future<String?> nextEvent() async {
    while (await _lines.moveNext().timeout(_wait)) {
      final line = _lines.current;
      if (line.startsWith('event: ')) return line.substring('event: '.length);
    }
    return null;
  }

  /// The names of the events until the stream ends.
  Future<List<String>> rest() async {
    final names = <String>[];
    for (var name = await nextEvent(); name != null; name = await nextEvent()) {
      names.add(name);
    }
    return names;
  }

  /// Whether the comment `: <text>` arrives before the stream ends.
  Future<bool> nextComment(String text) async {
    while (await _lines.moveNext().timeout(_wait)) {
      if (_lines.current == ': $text') return true;
    }
    return false;
  }

  /// Drops the connection.
  void close() => _client.close(force: true);
}
