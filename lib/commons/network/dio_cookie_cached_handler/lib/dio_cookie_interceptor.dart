import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'cookie_storage.dart';

/// Since we are using Dio's interceptor. This is the interceptor for cookie handling
final CookieStorage _sharedStorage = CookieStorage(
    getApplicationSupportDirectory()
        .then((value) => "${value.path}/.dio.cookies"));

/// Discard web sessions when the bound account changes.
Future<void> clearCachedCookies() => _sharedStorage.clear();

QueuedInterceptorsWrapper cookieCachedHandler() {
  return QueuedInterceptorsWrapper(
    onRequest: (options, handler) async {
      await _sharedStorage.loadToReq(options);
      handler.next(options);
    },
    onResponse: (res, handler) async {
      await _sharedStorage.storeFromRes(res);
      handler.next(res);
    },
    onError: (e, handler) async {
      final res = e.response;
      if (res != null) {
        await _sharedStorage.storeFromRes(res);
      }
      handler.next(e);
    },
  );
}
