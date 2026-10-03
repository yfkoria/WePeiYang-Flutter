import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:we_pei_yang_flutter/commons/preferences/common_prefs.dart';
import 'package:we_pei_yang_flutter/commons/themes/template/wpy_theme_data.dart';
import 'package:we_pei_yang_flutter/commons/util/text_util.dart';

import '../../../commons/themes/wpy_theme.dart';
import '../../../commons/widgets/w_button.dart';

class ScheduleSettingPage extends StatefulWidget {
  @override
  _ScheduleSettingPageState createState() => _ScheduleSettingPageState();
}

class _ScheduleSettingPageState extends State<ScheduleSettingPage>
    with WidgetsBindingObserver {
  static const _reminderChannel =
      MethodChannel('com.twt.service/class_reminder');
  Map<String, dynamic> _reminder = {};
  Timer? _silenceTestTimer;
  bool _silenceTestBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadReminder();
  }

  @override
  void dispose() {
    _silenceTestTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadReminder();
  }

  Future<void> _loadReminder() async {
    if (!Platform.isAndroid) return;
    try {
      final result =
          await _reminderChannel.invokeMapMethod<String, dynamic>('status');
      if (!mounted) return;
      setState(() => _reminder = result ?? {});
      _silenceTestTimer?.cancel();
      final until = _reminder['silenceTestUntil'] as int? ?? 0;
      final remaining = until - DateTime.now().millisecondsSinceEpoch;
      if (remaining > 0) {
        _silenceTestTimer =
            Timer(Duration(milliseconds: remaining + 300), _loadReminder);
      }
    } on PlatformException catch (e) {
      _showReminderError(e.message ?? '读取提醒设置失败');
    }
  }

  Future<void> _setReminder(String key, bool value) async {
    try {
      final result = await _reminderChannel.invokeMapMethod<String, dynamic>(
          'setOption', {'key': key, 'value': value});
      if (mounted) setState(() => _reminder = result ?? {});
    } on PlatformException catch (e) {
      _showReminderError(e.message ?? '保存提醒设置失败');
    }
  }

  Future<void> _testSilence() async {
    if (_silenceTestBusy) return;
    setState(() => _silenceTestBusy = true);
    try {
      final message = await _reminderChannel.invokeMethod<String>('testSilence');
      if (message != null) _showReminderError(message);
    } on PlatformException catch (e) {
      _showReminderError(e.message ?? '静音测试失败');
    } finally {
      await _loadReminder();
      if (mounted) setState(() => _silenceTestBusy = false);
    }
  }

  Future<void> _openReminderSetting(String kind) async {
    try {
      await _reminderChannel.invokeMethod('openSetting', {'kind': kind});
    } on PlatformException catch (e) {
      _showReminderError(e.message ?? '无法打开系统设置');
    }
  }

  void _showReminderError(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _reminderSwitch(String title, String key, {String? subtitle}) =>
      SwitchListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: _reminder[key] == true,
        onChanged:
            _reminder.isEmpty ? null : (value) => _setReminder(key, value),
      );

  Widget _permissionTile(String title, String key, String kind) => ListTile(
        title: Text(title),
        subtitle: Text(_reminder[key] == true ? '已开启' : '未开启，点击前往系统设置'),
        trailing: Icon(
            _reminder[key] == true ? Icons.check_circle : Icons.open_in_new),
        onTap: _reminder[key] == true ? null : () => _openReminderSetting(kind),
      );

  final upNumberList = ["5${'天'}", "6${'天'}", "7${'天'}"];
  final downNumberList = ['周一至周五', '周一至周六', '周一至周日'];
  int _index = CommonPreferences.dayNumber.value - 5;

  Widget _judgeIndex(int index) {
    if (index != _index)
      return SizedBox.shrink();
    else
      return Padding(
        padding: const EdgeInsets.only(right: 22),
        child: Icon(
          Icons.check,
          color: WpyTheme.of(context).get(WpyColorKey.basicTextColor),
        ),
      );
  }

  BorderRadius _judgeBorder(int index) {
    if (index == 0)
      return BorderRadius.vertical(top: Radius.circular(9));
    else if (index == 1)
      return BorderRadius.zero;
    else
      return BorderRadius.vertical(bottom: Radius.circular(9));
  }

  Widget _getNumberOfDaysCard(BuildContext context, int index) {
    final hintTextStyle = TextUtil.base.regular.sp(12).oldHint(context);
    final mainTextStyle =
        TextUtil.base.regular.sp(16.5).oldThirdAction(context);
    return InkWell(
      onTap: () {
        setState(() => _index = index);
        CommonPreferences.dayNumber.value = index + 5;
      },
      borderRadius: _judgeBorder(index),
      splashFactory: InkRipple.splashFactory,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 150,
                  child: Text(upNumberList[index], style: mainTextStyle),
                ),
                SizedBox(height: 3),
                SizedBox(
                  width: 150,
                  child: Text(downNumberList[index], style: hintTextStyle),
                )
              ],
            ),
            Spacer(),
            _judgeIndex(index)
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor:
              WpyTheme.of(context).get(WpyColorKey.primaryBackgroundColor),
          elevation: 0,
          leading: Padding(
            padding: const EdgeInsets.only(left: 15),
            child: WButton(
                child: Icon(Icons.arrow_back,
                    color: WpyTheme.of(context).get(WpyColorKey.oldActionColor),
                    size: 32),
                onPressed: () => Navigator.pop(context)),
          )),
      backgroundColor:
          WpyTheme.of(context).get(WpyColorKey.secondaryBackgroundColor),
      body: ListView(
        children: [
          Container(
            alignment: Alignment.centerLeft,
            margin: const EdgeInsets.fromLTRB(35, 20, 35, 0),
            child: Text(
              '课程表设置',
              style: TextUtil.base.bold.sp(28).oldFurthAction(context),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(35, 15, 35, 20),
            alignment: Alignment.centerLeft,
            child: Text(
              '调整每周显示天数、上课提醒与自动静音。',
              style: TextUtil.base.regular.sp(11.5).oldThirdAction(context),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            elevation: 0,
            color: WpyTheme.of(context).get(WpyColorKey.primaryBackgroundColor),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            child: Column(
              children: <Widget>[
                _getNumberOfDaysCard(context, 0),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 15),
                  height: 1,
                  color: WpyTheme.of(context).get(WpyColorKey.oldHintColor),
                ),
                _getNumberOfDaysCard(context, 1),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 15),
                  height: 1,
                  color: WpyTheme.of(context).get(WpyColorKey.oldHintColor),
                ),
                _getNumberOfDaysCard(context, 2),
              ],
            ),
          ),
          if (Platform.isAndroid) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(35, 30, 35, 8),
              child: Text('上课提醒',
                  style: TextUtil.base.bold.sp(22).oldFurthAction(context)),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              elevation: 0,
              color:
                  WpyTheme.of(context).get(WpyColorKey.primaryBackgroundColor),
              child: Column(children: [
                _reminderSwitch('启用上课提醒', 'enabled',
                    subtitle: '按课表发送通知；支持时尝试显示小米超级岛'),
                _reminderSwitch('提前 20 分钟', 'minute20'),
                _reminderSwitch('提前 10 分钟', 'minute10'),
                _reminderSwitch('提前 5 分钟', 'minute5'),
                _reminderSwitch('自动静音', 'silent',
                    subtitle: '上课前 5 分钟开启，下课后 5 分钟恢复原状态'),
                _permissionTile('通知权限', 'notifications', 'notifications'),
                _permissionTile('精确定时权限', 'exact', 'exact'),
                _permissionTile('勿扰模式控制权限', 'policy', 'policy'),
                ListTile(
                  title: Text((_reminder['silenceTestUntil'] as int? ?? 0) > 0
                      ? '结束静音测试并恢复'
                      : '测试静音（10 秒）'),
                  subtitle: Text(
                      '当前：${switch (_reminder['ringerMode']) { 0 => '静音', 1 => '振动', 2 => '正常响铃', _ => '读取中' }}\n'
                      '自动恢复测试前状态，不调整媒体或闹钟音量'),
                  trailing: Icon((_reminder['silenceTestUntil'] as int? ?? 0) > 0
                      ? Icons.undo
                      : Icons.volume_off_outlined),
                  onTap: _reminder.isEmpty || _silenceTestBusy
                      ? null
                      : _testSilence,
                ),
                ListTile(
                  title: const Text('测试顶部提醒（2 分 05 秒）'),
                  subtitle: Text(
                      '演示：高等数学 A（上）· 张明 · 45教 A203\n'
                      '发送后返回桌面查看倒计时\n'
                      '超级岛协议 ${_reminder['protocol'] ?? 0} · 焦点权限${_reminder['focus'] == true ? '已开' : '未开'}'),
                  trailing: const Icon(Icons.notifications_active_outlined),
                  onTap: () async {
                    try {
                      await _reminderChannel.invokeMethod('test');
                    } on PlatformException catch (e) {
                      _showReminderError(e.message ?? '测试通知失败');
                    }
                  },
                ),
              ]),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
