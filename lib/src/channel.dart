import 'package:stream_channel/stream_channel.dart';

// ignore: uri_does_not_exist
import '_connect_api.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) '_connect_html.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) '_connect_io.dart' as platform;

abstract class SseChannel extends StreamChannelMixin {
  factory SseChannel.connect(Uri url) => platform.connect(url);

  /// Closes the SSE stream and releases the underlying connection.
  ///
  /// Without this, the HTTP GET socket of the event stream stays open until
  /// the server closes it. When the local network interface disappears (for
  /// example a dropped VPN tunnel) the server can never do that, so the dead
  /// socket stays ESTABLISHED forever.
  void close();
}
