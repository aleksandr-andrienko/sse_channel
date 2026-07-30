import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pool/pool.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/uuid.dart';

import 'src/event_source_transformer.dart';
import 'src/sse_channel_exception.dart';

final _requestPool = Pool(1000);

typedef OnConnected = void Function();

class IOSseChannel extends StreamChannelMixin implements SseChannel {
  int _lastMessageId = -1;
  final Uri _serverUrl;
  final String _clientId;
  http.Client? _client;
  StreamSubscription? _responseSubscription;
  bool _closed = false;
  late final StreamController<String?> _incomingController;
  late final StreamController<String?> _outgoingController;
  final _onConnected = Completer();

  IOSseChannel._(
    Uri serverUrl,
  )   : _serverUrl = serverUrl,
        _clientId = Uuid().v4(),
        _outgoingController = StreamController<String?>() {
    _client = http.Client();
    _incomingController =
        StreamController<String?>.broadcast(onListen: () async {
      final client = _client;
      if (client == null) {
        // close() ran before the first listener attached.
        return;
      }

      var queryParameters =
          Map<String, String>.from(_serverUrl.queryParameters);

      final request = http.Request(
        'GET',
        _serverUrl.replace(
            queryParameters: queryParameters
              ..addAll({'sseClientId': _clientId})),
      )..headers['Accept'] = 'text/event-stream';

      await client.send(request).then((response) {
        if (response.statusCode == 200) {
          _responseSubscription = response.stream
              .transform(EventSourceTransformer())
              .listen((event) {
            _incomingController.sink.add(event.data);
          });

          _onConnected.complete();
        } else {
          _incomingController.addError(SseChannelException(
              'Failed to connect to ${_serverUrl.toString()}',
              "${response.statusCode}:${response.reasonPhrase}"));
        }
      });
    }, onCancel: close);

    _onConnected.future.whenComplete(
      () => _outgoingController.stream.listen(_onOutgoingMessage),
    );
  }

  factory IOSseChannel.connect(Uri url) {
    return IOSseChannel._(
      url,
    );
  }

  @override
  StreamSink get sink => _outgoingController.sink;

  @override
  Stream get stream => _incomingController.stream;

  /// Closes the event stream and the underlying HTTP connection.
  ///
  /// Cancelling the response subscription and closing the [http.Client] is
  /// what actually terminates the GET socket. Previously only the stream
  /// controller was closed, which left the socket ESTABLISHED forever when
  /// the local network interface disappeared (dropped VPN tunnel).
  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;

    _responseSubscription?.cancel();
    _responseSubscription = null;
    _client?.close();
    _client = null;

    if (!_incomingController.isClosed) {
      _incomingController.close();
    }
    if (!_outgoingController.isClosed) {
      _outgoingController.close();
    }
  }

  Future<void> _onOutgoingMessage(String? message) async {
    String? encodedMessage;
    await _requestPool.withResource(() async {
      try {
        encodedMessage = jsonEncode(message);
      } on JsonUnsupportedObjectError {
        //_logger.warning('[$_clientId] Unable to encode outgoing message: $e');
      } on ArgumentError {
        //_logger.warning('[$_clientId] Invalid argument: $e');
      }
      try {
        final url =
            '$_serverUrl?sseClientId=$_clientId&messageId=${_lastMessageId++}';
        await http.post(Uri.parse(url), body: encodedMessage);
      } catch (error) {
        //final augmentedError =
        //    '[$_clientId] SSE client failed to send $message:\n $error';
        //_logger.severe(augmentedError);
        //_closeWithError(augmentedError);
      }
    });
  }
}
