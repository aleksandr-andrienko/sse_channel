class SseChannelException implements Exception {
  String message;
  String data;
  SseChannelException(this.message, this.data);
}
