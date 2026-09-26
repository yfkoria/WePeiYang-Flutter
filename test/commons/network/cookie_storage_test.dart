import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio_cookie_caching_handler/cookie_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clear removes persisted cookies before the first request', () async {
    final directory = await Directory.systemTemp.createTemp('wpy-cookies-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/cookies');
    await file.writeAsString('JSESSIONID=old;2099-01-01T00:00:00.000Z\n');

    final storage = CookieStorage(Future.value(file.path));
    await storage.clear();

    expect(await file.readAsString(), isEmpty);
    final request = RequestOptions(path: '/test');
    await storage.loadToReq(request);
    expect(request.headers.containsKey('cookie'), isFalse);
  });
}
