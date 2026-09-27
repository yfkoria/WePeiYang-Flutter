import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

Future<void> main() async {
  final adb = await Process.run(
    '/Users/yfkoria/Library/Android/sdk/platform-tools/adb',
    [
      '-s',
      'emulator-5554',
      'exec-out',
      'run-as',
      'com.twt.service.develop',
      'cat',
      'files/.dio.cookies',
    ],
  );
  if (adb.exitCode != 0) throw StateError('App session unavailable');

  final prefsResult = await Process.run(
    '/Users/yfkoria/Library/Android/sdk/platform-tools/adb',
    [
      '-s', 'emulator-5554', 'exec-out', 'run-as',
      'com.twt.service.develop', 'cat',
      'shared_prefs/FlutterSharedPreferences.xml',
    ],
  );
  final prefsXml = prefsResult.exitCode == 0 ? prefsResult.stdout as String : '';
  String pref(String key) => RegExp('<string name="flutter\\.$key">([^<]*)</string>')
      .firstMatch(prefsXml)?.group(1) ?? '';
  final appUsername = pref('tjuuname');
  final appUserNumber = pref('userNumber');
  final appRealName = pref('realName');
  print('appPrefs: hasTjuUsername=${appUsername.isNotEmpty}, '
      'tjuUsernameLength=${appUsername.length}, '
      'sameAsAppUserNumber=${appUsername.isNotEmpty && appUsername == appUserNumber}');

  final cookies = <String, String>{};
  for (final line in (adb.stdout as String).split('\n')) {
    final equal = line.indexOf('=');
    final semicolon = line.indexOf(';', equal + 1);
    if (equal > 0 && semicolon > equal) {
      cookies[line.substring(0, equal)] = line.substring(equal + 1, semicolon);
    }
  }
  print('session: cookieNames=${cookies.keys.toList()..sort()}');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);

  Future<String> request(String path, {Map<String, String>? form}) async {
    final uri = Uri.parse('https://classes.tju.edu.cn/eams/courseTableForStd!$path');
    final req = form == null ? await client.getUrl(uri) : await client.postUrl(uri);
    req.headers.set(HttpHeaders.cookieHeader,
        cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '));
    if (form != null) {
      req.headers.contentType = ContentType(
          'application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: form).query);
    }
    final response = await req.close();
    for (final cookie in response.cookies) {
      cookies[cookie.name] = cookie.value;
    }
    final body = await utf8.decoder.bind(response).join();
    print('$path: status=${response.statusCode}, length=${body.length}, '
        'redirects=${response.redirects.length}, '
        'loginPage=${body.contains('统一认证系统')}');
    return body;
  }

  try {
    final semesterId = cookies['semester.id'] ?? '';
    print('request: hasSemester=${semesterId.isNotEmpty}, semesterId=$semesterId');
    final index = await request('index.action?projectId=1');
    final inner = await request('innerIndex.action?projectId=1');
    final homeRequest = await client.getUrl(
      Uri.parse('https://classes.tju.edu.cn/eams/home.action'),
    );
    homeRequest.headers.set(HttpHeaders.cookieHeader,
        cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '));
    final homeResponse = await homeRequest.close();
    final homeBody = await utf8.decoder.bind(homeResponse).join();
    print('home: status=${homeResponse.statusCode}, length=${homeBody.length}, '
        'appUsernamePresent=${appUsername.isNotEmpty && homeBody.contains(appUsername)}, '
        'appRealNamePresent=${appRealName.isNotEmpty && homeBody.contains(appRealName)}');
    final ids = RegExp(r'"ids","([^"]+)"').firstMatch(inner)?.group(1) ?? '';
    print('index/inner: indexHasGrid=${index.contains('courseTable')}, '
        'hasIds=${ids.isNotEmpty}, idsLength=${ids.length}, '
        'appUsernameInIndex=${appUsername.isNotEmpty && index.contains(appUsername)}, '
        'appUsernameInInner=${appUsername.isNotEmpty && inner.contains(appUsername)}, '
        'appRealNameInIndex=${appRealName.isNotEmpty && index.contains(appRealName)}, '
        'appRealNameInInner=${appRealName.isNotEmpty && inner.contains(appRealName)}');
    if (semesterId.isEmpty || ids.isEmpty) return;
    final body = await request('courseTable.action', form: {
      'ignoreHead': '1',
      'setting.kind': 'std',
      'startWeek': '',
      'semester.id': semesterId,
      'ids': ids,
    });
    final document = html.parse(body);
    print('payload: taskActivities=${RegExp(r'new\s+TaskActivity\s*\(').allMatches(body).length}, '
        'teachers=${RegExp(r'var\s+teachers\b').allMatches(body).length}, '
        'fillTable=${body.contains('fillTable')}, '
        'plainTd=${RegExp(r'<td>').allMatches(body).length}');
    final tbodies = document.querySelectorAll('tbody');
    for (var i = 0; i < tbodies.length; i++) {
      final rows = tbodies[i].querySelectorAll('tr');
      print('tbody[$i]: rows=${rows.length}, '
          'tds=${tbodies[i].querySelectorAll('td').length}, '
          'rowWidths=${rows.take(4).map((row) => row.querySelectorAll('td').length).toList()}');
    }
    final tables = document.querySelectorAll('table');
    for (var i = 0; i < tables.length; i++) {
      print('table[$i]: id=${tables[i].id}, '
          'rows=${tables[i].querySelectorAll('tr').length}, '
          'tds=${tables[i].querySelectorAll('td').length}');
    }
  } finally {
    client.close(force: true);
  }
}
