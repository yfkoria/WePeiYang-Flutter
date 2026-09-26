import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:we_pei_yang_flutter/commons/preferences/common_prefs.dart';
import 'package:we_pei_yang_flutter/commons/themes/template/wpy_theme_data.dart';
import 'package:we_pei_yang_flutter/commons/themes/wpy_theme.dart';
import 'package:we_pei_yang_flutter/commons/util/toast_provider.dart';
import 'package:we_pei_yang_flutter/schedule/model/course_provider.dart';
import 'package:we_pei_yang_flutter/schedule/model/schedule_adjustment.dart';

Future<void> showScheduleAdjustmentSheet(BuildContext context) {
  final provider = context.read<CourseProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (_) => ChangeNotifierProvider.value(
      value: provider,
      child: const ScheduleAdjustmentSheet(),
    ),
  );
}

class ScheduleAdjustmentSheet extends StatefulWidget {
  const ScheduleAdjustmentSheet({super.key});

  @override
  State<ScheduleAdjustmentSheet> createState() =>
      _ScheduleAdjustmentSheetState();
}

class _ScheduleAdjustmentSheetState extends State<ScheduleAdjustmentSheet> {
  static const _weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  late ScheduleAdjustmentType _type;
  late int _sourceWeek;
  late int _sourceWeekday;
  late int _targetWeek;
  late int _targetWeekday;

  @override
  void initState() {
    super.initState();
    final provider = context.read<CourseProvider>();
    _type = ScheduleAdjustmentType.move;
    _sourceWeek = provider.selectedWeek;
    _sourceWeekday = provider.selectedWeek == provider.currentWeek
        ? DateTime.now().weekday
        : DateTime.monday;

    if (_sourceWeekday == DateTime.sunday && _sourceWeek < provider.weekCount) {
      _targetWeek = _sourceWeek + 1;
      _targetWeekday = DateTime.monday;
    } else if (_sourceWeekday == DateTime.sunday) {
      _targetWeek = _sourceWeek;
      _targetWeekday = DateTime.saturday;
    } else {
      _targetWeek = _sourceWeek;
      _targetWeekday = _sourceWeekday + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseProvider>();
    final source = TeachingDay(week: _sourceWeek, weekday: _sourceWeekday);
    final target = TeachingDay(week: _targetWeek, weekday: _targetWeekday);
    final preview = provider.previewScheduleAdjustment(
      type: _type,
      source: source,
      target: _type == ScheduleAdjustmentType.move ? target : null,
    );
    final targetIsHidden = _type == ScheduleAdjustmentType.move &&
        target.weekday > CommonPreferences.dayNumber.value;
    final primary = WpyTheme.of(context).get(WpyColorKey.primaryActionColor);
    final background =
        WpyTheme.of(context).get(WpyColorKey.secondaryBackgroundColor);

    return Material(
      color: background,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              '调休',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4.h),
            Text(
              '只调整选中日期的学校课程，自定义课程和其他周保持不变。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 18.h),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('平移到另一天'),
                    selected: _type == ScheduleAdjustmentType.move,
                    onSelected: (_) =>
                        setState(() => _type = ScheduleAdjustmentType.move),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('删除当天课程'),
                    selected: _type == ScheduleAdjustmentType.delete,
                    onSelected: (_) =>
                        setState(() => _type = ScheduleAdjustmentType.delete),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18.h),
            _DaySelector(
              title: '起始日期',
              weekCount: provider.weekCount,
              week: _sourceWeek,
              weekday: _sourceWeekday,
              dateLabel: _dateLabel(source),
              onWeekChanged: (value) => setState(() => _sourceWeek = value),
              onWeekdayChanged: (value) =>
                  setState(() => _sourceWeekday = value),
            ),
            if (_type == ScheduleAdjustmentType.move) ...[
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8.h),
                child: Icon(Icons.arrow_downward_rounded, color: primary),
              ),
              _DaySelector(
                title: '目标日期',
                weekCount: provider.weekCount,
                week: _targetWeek,
                weekday: _targetWeekday,
                dateLabel: _dateLabel(target),
                onWeekChanged: (value) => setState(() => _targetWeek = value),
                onWeekdayChanged: (value) =>
                    setState(() => _targetWeekday = value),
              ),
            ],
            SizedBox(height: 16.h),
            _PreviewMessage(preview: preview, targetIsHidden: targetIsHidden),
            SizedBox(height: 16.h),
            ElevatedButton(
              onPressed: preview.canApply
                  ? () => _confirmAndApply(provider, preview)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                minimumSize: Size.fromHeight(46.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r),
                ),
              ),
              child: Text(
                _type == ScheduleAdjustmentType.move ? '确认平移' : '确认删除',
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(TeachingDay day) {
    final termStart = DateTime.fromMillisecondsSinceEpoch(
      CommonPreferences.termStart.value * 1000,
    );
    final date = DateTime(
      termStart.year,
      termStart.month,
      termStart.day,
    ).add(Duration(days: (day.week - 1) * 7 + day.weekday - 1));
    return '${date.month}月${date.day}日';
  }

  Future<void> _confirmAndApply(
    CourseProvider provider,
    ScheduleAdjustmentPreview preview,
  ) async {
    final adjustmentCount = '${preview.affectedCourseCount} 门课的 '
        '${preview.affectedArrangeCount} 条课程安排';
    var detail = preview.type == ScheduleAdjustmentType.delete
        ? '将删除当天 $adjustmentCount。'
        : '将平移 $adjustmentCount。';
    if (preview.conflictCount > 0) {
      detail += '\n目标日期存在 ${preview.conflictCount} 处时间冲突，'
          '平移后将以冲突课程显示。';
    }
    if (preview.target != null &&
        preview.target!.weekday > CommonPreferences.dayNumber.value) {
      detail += '\n目标星期当前未在课表中显示，可在课表设置中开启。';
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              preview.type == ScheduleAdjustmentType.delete
                  ? '确认删除当天课程？'
                  : '确认平移当天课程？',
            ),
            content: Text(detail),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final result = provider.applyScheduleAdjustment(
      type: preview.type,
      source: preview.source,
      target: preview.target,
    );
    if (!result.canApply) {
      ToastProvider.error(result.error ?? '调整失败，请重试');
      return;
    }
    Navigator.pop(context);
    ToastProvider.success(
      preview.type == ScheduleAdjustmentType.delete ? '已删除当天课程' : '已平移当天课程',
    );
  }
}

class _DaySelector extends StatelessWidget {
  final String title;
  final int weekCount;
  final int week;
  final int weekday;
  final String dateLabel;
  final ValueChanged<int> onWeekChanged;
  final ValueChanged<int> onWeekdayChanged;

  const _DaySelector({
    required this.title,
    required this.weekCount,
    required this.week,
    required this.weekday,
    required this.dateLabel,
    required this.onWeekChanged,
    required this.onWeekdayChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(dateLabel, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: week,
                decoration: const InputDecoration(
                  labelText: '教学周',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: List.generate(
                  weekCount,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('第 ${index + 1} 周'),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) onWeekChanged(value);
                },
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: weekday,
                decoration: const InputDecoration(
                  labelText: '星期',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: List.generate(
                  _ScheduleAdjustmentSheetState._weekdays.length,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text(_ScheduleAdjustmentSheetState._weekdays[index]),
                  ),
                ),
                onChanged: (value) {
                  if (value != null) onWeekdayChanged(value);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PreviewMessage extends StatelessWidget {
  final ScheduleAdjustmentPreview preview;
  final bool targetIsHidden;

  const _PreviewMessage({required this.preview, required this.targetIsHidden});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String text;
    if (preview.error != null) {
      color = Theme.of(context).colorScheme.error;
      icon = Icons.error_outline;
      text = preview.error!;
    } else if (preview.conflictCount > 0 || targetIsHidden) {
      color = Colors.orange.shade800;
      icon = Icons.warning_amber_rounded;
      final warnings = <String>[];
      if (preview.conflictCount > 0) {
        warnings.add('目标日期有 ${preview.conflictCount} 处时间冲突');
      }
      if (targetIsHidden) warnings.add('目标星期当前未显示');
      final warningText = warnings.join('，');
      text = '将调整 ${preview.affectedCourseCount} 门课、'
          '${preview.affectedArrangeCount} 条安排；$warningText。';
    } else {
      color = Theme.of(context).colorScheme.primary;
      icon = Icons.check_circle_outline;
      text = '将调整 ${preview.affectedCourseCount} 门课的 '
          '${preview.affectedArrangeCount} 条课程安排。';
    }

    return Container(
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20.r),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
