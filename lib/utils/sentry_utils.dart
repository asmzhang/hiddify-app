import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Scrubs subscription credentials before anything leaves the process (audit C).
///
/// Log messages like `subscription restored from [https://panel/sub?token=…]`
/// used to reach Sentry breadcrumbs verbatim. Query strings of subscription /
/// deep links carry the private token, so every `?…` / `&…` tail on an
/// http(s) URL is replaced regardless of parameter name (no allowlist to
/// forget). Returns the input unchanged when nothing matches.
/// Query part stops at whitespace / `)` / `]` so log wrappers like
/// `[…?token=x]` keep their closing bracket.
final RegExp _tokenizedUrlPattern = RegExp(r'(https?://[^\s?]+)\?([^\s\])]*)');

String scrubSensitiveUrls(String input) {
  return input.replaceAllMapped(_tokenizedUrlPattern, (m) => '${m.group(1)}?…');
}

FutureOr<SentryEvent?> sentryBeforeSend(SentryEvent event, {Hint? hint}) {
  if (canSendEvent(event.throwable)) return event;
  return null;
}

bool canSendEvent(dynamic throwable) {
  return switch (throwable) {
    UnexpectedFailure(:final error) => canSendEvent(error),
    DioException _ => false,
    SocketException _ => false,
    UnknownIp _ => false,
    HttpException _ => false,
    HandshakeException _ => false,
    ExpectedFailure _ => false,
    ExpectedMeasuredFailure _ => false,
    _ => true,
  };
}

bool canLogEvent(dynamic throwable) => switch (throwable) {
  ExpectedMeasuredFailure _ => true,
  _ => canSendEvent(throwable),
};
