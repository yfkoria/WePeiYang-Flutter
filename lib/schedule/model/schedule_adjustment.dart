import 'package:we_pei_yang_flutter/schedule/model/course.dart';

enum ScheduleAdjustmentType { delete, move }

/// A single calendar day in the teaching term.
class TeachingDay {
  final int week;
  final int weekday;

  const TeachingDay({required this.week, required this.weekday});

  @override
  bool operator ==(Object other) =>
      other is TeachingDay && week == other.week && weekday == other.weekday;

  @override
  int get hashCode => Object.hash(week, weekday);
}

class ScheduleAdjustmentPreview {
  final ScheduleAdjustmentType type;
  final TeachingDay source;
  final TeachingDay? target;
  final int affectedCourseCount;
  final int affectedArrangeCount;
  final int conflictCount;
  final String? error;

  const ScheduleAdjustmentPreview({
    required this.type,
    required this.source,
    required this.target,
    required this.affectedCourseCount,
    required this.affectedArrangeCount,
    required this.conflictCount,
    this.error,
  });

  bool get canApply => error == null && affectedArrangeCount > 0;
}

class _CourseArrange {
  final Course course;
  final Arrange arrange;

  const _CourseArrange(this.course, this.arrange);
}

/// Pure schedule-adjustment logic. Keeping it independent from Flutter makes
/// validation and mutations deterministic and easy to test.
class ScheduleAdjustment {
  const ScheduleAdjustment._();

  static ScheduleAdjustmentPreview preview({
    required List<Course> courses,
    required int weekCount,
    required ScheduleAdjustmentType type,
    required TeachingDay source,
    TeachingDay? target,
  }) {
    final validationError = _validate(
      weekCount: weekCount,
      type: type,
      source: source,
      target: target,
    );
    if (validationError != null) {
      return ScheduleAdjustmentPreview(
        type: type,
        source: source,
        target: target,
        affectedCourseCount: 0,
        affectedArrangeCount: 0,
        conflictCount: 0,
        error: validationError,
      );
    }

    final sourceArranges = _activeArranges(courses, source, schoolOnly: true);
    if (sourceArranges.isEmpty) {
      return ScheduleAdjustmentPreview(
        type: type,
        source: source,
        target: target,
        affectedCourseCount: 0,
        affectedArrangeCount: 0,
        conflictCount: 0,
        error: '该日没有可调整的学校课程',
      );
    }

    var conflictCount = 0;
    if (type == ScheduleAdjustmentType.move) {
      final targetArranges = _activeArranges(courses, target!);
      for (final sourceArrange in sourceArranges) {
        for (final targetArrange in targetArranges) {
          if (_overlaps(sourceArrange.arrange, targetArrange.arrange)) {
            conflictCount++;
          }
        }
      }
    }

    return ScheduleAdjustmentPreview(
      type: type,
      source: source,
      target: target,
      affectedCourseCount:
          sourceArranges.map((entry) => entry.course).toSet().length,
      affectedArrangeCount: sourceArranges.length,
      conflictCount: conflictCount,
    );
  }

  /// Applies an adjustment only after running the same validation as [preview].
  /// The returned preview describes the mutation that was applied.
  static ScheduleAdjustmentPreview apply({
    required List<Course> courses,
    required int weekCount,
    required ScheduleAdjustmentType type,
    required TeachingDay source,
    TeachingDay? target,
  }) {
    final result = preview(
      courses: courses,
      weekCount: weekCount,
      type: type,
      source: source,
      target: target,
    );
    if (!result.canApply) return result;

    // Capture occurrences before mutating the arrange lists. This is
    // especially important when several arrangements belong to one course.
    final sourceArranges = _activeArranges(courses, source, schoolOnly: true);
    final affectedCourses = sourceArranges.map((entry) => entry.course).toSet();
    for (final entry in sourceArranges) {
      entry.arrange.weekList.remove(source.week);
    }

    if (type == ScheduleAdjustmentType.move) {
      for (final entry in sourceArranges) {
        final arrange = entry.arrange;
        entry.course.arrangeList.add(
          Arrange(
            name: arrange.name,
            location: arrange.location,
            weekday: target!.weekday,
            weekList: [target.week],
            unitList: List<int>.of(arrange.unitList),
            teacherList: List<String>.of(arrange.teacherList),
            showMode: 0,
            isExperiment: arrange.isExperiment,
          ),
        );
      }
    }

    for (final course in affectedCourses) {
      course.arrangeList.removeWhere((arrange) => arrange.weekList.isEmpty);
      final activeWeeks = course.arrangeList
          .expand((arrange) => arrange.weekList)
          .toSet()
          .toList()
        ..sort();
      if (activeWeeks.isEmpty) {
        course.weeks = '';
      } else {
        course.weeks = '${activeWeeks.first}-${activeWeeks.last}';
      }
    }
    courses.removeWhere((course) =>
        affectedCourses.contains(course) && course.arrangeList.isEmpty);
    return result;
  }

  static String? _validate({
    required int weekCount,
    required ScheduleAdjustmentType type,
    required TeachingDay source,
    required TeachingDay? target,
  }) {
    if (weekCount < 1) return '学期周数配置无效';
    if (!_isValidDay(source, weekCount)) return '起始日期不在本学期内';
    if (type == ScheduleAdjustmentType.move) {
      if (target == null) return '请选择目标日期';
      if (!_isValidDay(target, weekCount)) return '目标日期不在本学期内';
      if (target == source) return '目标日期不能与起始日期相同';
    }
    return null;
  }

  static bool _isValidDay(TeachingDay day, int weekCount) =>
      day.week >= 1 &&
      day.week <= weekCount &&
      day.weekday >= DateTime.monday &&
      day.weekday <= DateTime.sunday;

  static List<_CourseArrange> _activeArranges(
    List<Course> courses,
    TeachingDay day, {
    bool schoolOnly = false,
  }) {
    final result = <_CourseArrange>[];
    for (final course in courses) {
      // 自定义课程仍参与目标日期的冲突检查，但不能被调休修改。
      if (schoolOnly && course.type != 0) continue;
      for (final arrange in course.arrangeList) {
        if (arrange.weekday == day.weekday &&
            arrange.weekList.contains(day.week)) {
          result.add(_CourseArrange(course, arrange));
        }
      }
    }
    return result;
  }

  static bool _overlaps(Arrange first, Arrange second) {
    if (first.unitList.length < 2 || second.unitList.length < 2) return false;
    return first.unitList.first <= second.unitList.last &&
        second.unitList.first <= first.unitList.last;
  }
}
