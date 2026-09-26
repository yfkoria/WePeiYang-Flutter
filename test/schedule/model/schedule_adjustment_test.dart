import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:we_pei_yang_flutter/schedule/model/course.dart';
import 'package:we_pei_yang_flutter/schedule/model/schedule_adjustment.dart';
import 'package:we_pei_yang_flutter/schedule/model/week_list_codec.dart';

void main() {
  group('ScheduleAdjustment', () {
    for (final type in ScheduleAdjustmentType.values) {
      test(
          '$type leaves same-day custom courses and empty custom entries intact',
          () {
        final school = _course(name: 'School', type: 0, arranges: [
          _arrange(weekday: 1, weeks: [2], units: [1, 2]),
        ]);
        final custom = _course(name: 'Personal', type: 1, arranges: [
          _arrange(weekday: 1, weeks: [1, 2, 3], units: [3, 4]),
        ]);
        final emptyCustom =
            _course(name: 'Empty personal', type: 1, arranges: []);
        final courses = [school, custom, emptyCustom];
        final before = jsonEncode([custom, emptyCustom]);
        final preview = ScheduleAdjustment.preview(
          courses: courses,
          weekCount: 24,
          type: type,
          source: const TeachingDay(week: 2, weekday: 1),
          target: const TeachingDay(week: 2, weekday: 2),
        );
        expect(preview.canApply, isTrue);
        expect(preview.affectedCourseCount, 1);
        expect(preview.affectedArrangeCount, 1);

        final result = ScheduleAdjustment.apply(
          courses: courses,
          weekCount: 24,
          type: type,
          source: const TeachingDay(week: 2, weekday: 1),
          target: const TeachingDay(week: 2, weekday: 2),
        );
        expect(result.canApply, isTrue);
        expect(courses, containsAll([custom, emptyCustom]));
        expect(jsonEncode([custom, emptyCustom]), before);
        if (type == ScheduleAdjustmentType.move) {
          expect(school.arrangeList.single.weekday, 2);
        } else {
          expect(courses, isNot(contains(school)));
        }
      });

      test('$type rejects a day containing only custom courses', () {
        final courses = [
          _course(name: 'Personal', type: 1, arranges: [
            _arrange(weekday: 1, weeks: [2], units: [1, 2]),
          ])
        ];
        final before = jsonEncode(courses);
        final result = ScheduleAdjustment.apply(
          courses: courses,
          weekCount: 24,
          type: type,
          source: const TeachingDay(week: 2, weekday: 1),
          target: const TeachingDay(week: 2, weekday: 2),
        );
        expect(result.canApply, isFalse);
        expect(result.error, '该日没有可调整的学校课程');
        expect(jsonEncode(courses), before);
      });
    }

    test('deletes only the selected day occurrence', () {
      final mondayCourse = _course(
        name: 'Monday course',
        type: 0,
        arranges: [
          _arrange(weekday: 1, weeks: [1, 2, 3], units: [1, 2]),
        ],
      );
      final tuesdayCourse = _course(
        name: 'Tuesday course',
        type: 1,
        arranges: [
          _arrange(weekday: 2, weeks: [2], units: [3, 4]),
        ],
      );

      final result = ScheduleAdjustment.apply(
        courses: [mondayCourse, tuesdayCourse],
        weekCount: 24,
        type: ScheduleAdjustmentType.delete,
        source: const TeachingDay(week: 2, weekday: 1),
      );

      expect(result.canApply, isTrue);
      expect(result.affectedCourseCount, 1);
      expect(result.affectedArrangeCount, 1);
      expect(mondayCourse.arrangeList.single.weekList, [1, 3]);
      expect(mondayCourse.weeks, '1-3');
      expect(tuesdayCourse.arrangeList.single.weekList, [2]);
    });

    test(
      'moves all selected-day arrangements without changing other weeks',
      () {
        final course = _course(
          name: 'Physics',
          type: 0,
          arranges: [
            _arrange(
              weekday: 1,
              weeks: [1, 2, 3],
              units: [3, 4],
              location: 'Building 1',
              teachers: ['Teacher A'],
            ),
            _arrange(weekday: 1, weeks: [2], units: [5, 6]),
          ],
        );

        final result = ScheduleAdjustment.apply(
          courses: [course],
          weekCount: 24,
          type: ScheduleAdjustmentType.move,
          source: const TeachingDay(week: 2, weekday: 1),
          target: const TeachingDay(week: 3, weekday: 4),
        );

        expect(result.canApply, isTrue);
        expect(result.affectedArrangeCount, 2);
        expect(
          course.arrangeList
              .where((arrange) => arrange.weekday == 1)
              .single
              .weekList,
          [1, 3],
        );
        final moved = course.arrangeList
            .where(
              (arrange) => arrange.weekday == 4 && arrange.weekList.contains(3),
            )
            .toList();
        expect(moved, hasLength(2));
        expect(moved.first.location, 'Building 1');
        expect(moved.first.teacherList, ['Teacher A']);
        expect(
          moved.map((arrange) => arrange.unitList),
          contains(equals([3, 4])),
        );
        expect(
          moved.map((arrange) => arrange.unitList),
          contains(equals([5, 6])),
        );
      },
    );

    test('removes empty source arrange after moving its only occurrence', () {
      final course = _course(
        name: 'One-off course',
        type: 0,
        arranges: [
          _arrange(weekday: 5, weeks: [8], units: [1, 2]),
        ],
      );

      ScheduleAdjustment.apply(
        courses: [course],
        weekCount: 24,
        type: ScheduleAdjustmentType.move,
        source: const TeachingDay(week: 8, weekday: 5),
        target: const TeachingDay(week: 8, weekday: 6),
      );

      expect(course.arrangeList, hasLength(1));
      expect(course.arrangeList.single.weekday, 6);
      expect(course.arrangeList.single.weekList, [8]);
      expect(course.weeks, '8-8');
    });

    test('removes a one-off course after deleting its only occurrence', () {
      final course = _course(
        name: 'One-off course',
        type: 0,
        arranges: [
          _arrange(weekday: 5, weeks: [8], units: [1, 2]),
        ],
      );
      final courses = [course];

      final result = ScheduleAdjustment.apply(
        courses: courses,
        weekCount: 24,
        type: ScheduleAdjustmentType.delete,
        source: const TeachingDay(week: 8, weekday: 5),
      );

      expect(result.canApply, isTrue);
      expect(courses, isEmpty);
    });

    test('previews target conflicts without mutating courses', () {
      final moving = _course(
        name: 'Moving',
        type: 0,
        arranges: [
          _arrange(weekday: 1, weeks: [4], units: [3, 4]),
        ],
      );
      final existing = _course(
        name: 'Existing',
        type: 1,
        arranges: [
          _arrange(weekday: 2, weeks: [4], units: [4, 5]),
        ],
      );

      final preview = ScheduleAdjustment.preview(
        courses: [moving, existing],
        weekCount: 24,
        type: ScheduleAdjustmentType.move,
        source: const TeachingDay(week: 4, weekday: 1),
        target: const TeachingDay(week: 4, weekday: 2),
      );

      expect(preview.canApply, isTrue);
      expect(preview.conflictCount, 1);
      expect(moving.arrangeList.single.weekList, [4]);
      expect(moving.arrangeList.single.weekday, 1);
    });

    test('rejects same source and target without mutation', () {
      final course = _course(
        name: 'Course',
        type: 0,
        arranges: [
          _arrange(weekday: 3, weeks: [6], units: [1, 2]),
        ],
      );

      final result = ScheduleAdjustment.apply(
        courses: [course],
        weekCount: 24,
        type: ScheduleAdjustmentType.move,
        source: const TeachingDay(week: 6, weekday: 3),
        target: const TeachingDay(week: 6, weekday: 3),
      );

      expect(result.canApply, isFalse);
      expect(result.error, '目标日期不能与起始日期相同');
      expect(course.arrangeList.single.weekList, [6]);
    });

    test('rejects a day outside the teaching term and an empty day', () {
      final course = _course(
        name: 'Course',
        type: 0,
        arranges: [
          _arrange(weekday: 1, weeks: [1], units: [1, 2]),
        ],
      );

      final outside = ScheduleAdjustment.preview(
        courses: [course],
        weekCount: 24,
        type: ScheduleAdjustmentType.delete,
        source: const TeachingDay(week: 25, weekday: 1),
      );
      final empty = ScheduleAdjustment.preview(
        courses: [course],
        weekCount: 24,
        type: ScheduleAdjustmentType.delete,
        source: const TeachingDay(week: 1, weekday: 7),
      );

      expect(outside.canApply, isFalse);
      expect(outside.error, '起始日期不在本学期内');
      expect(empty.canApply, isFalse);
      expect(empty.error, '该日没有可调整的学校课程');
    });

    test('adjusted schedule survives the course-table JSON round trip', () {
      final course = _course(
        name: 'Persisted course',
        type: 0,
        arranges: [
          _arrange(weekday: 2, weeks: [1, 2, 3], units: [7, 8]),
        ],
      );

      ScheduleAdjustment.apply(
        courses: [course],
        weekCount: 24,
        type: ScheduleAdjustmentType.move,
        source: const TeachingDay(week: 2, weekday: 2),
        target: const TeachingDay(week: 2, weekday: 5),
      );
      final restored = CourseTable.fromJson(
        json.decode(json.encode(CourseTable([course], const []))),
      ).schoolCourses.single;

      expect(
        restored.arrangeList
            .singleWhere((arrange) => arrange.weekday == 2)
            .weekList,
        [1, 3],
      );
      expect(
        restored.arrangeList
            .singleWhere((arrange) => arrange.weekday == 5)
            .weekList,
        [2],
      );
    });
  });

  group('encodeWeekListRanges', () {
    test('keeps continuous and alternating ranges compact', () {
      expect(encodeWeekListRanges([1, 2, 3, 4]), ['[1-4]']);
      expect(encodeWeekListRanges([1, 3, 5, 7]), ['[1-7]单']);
      expect(encodeWeekListRanges([2, 4, 6]), ['[2-6]双']);
    });

    test('splits a range around a removed teaching week', () {
      expect(encodeWeekListRanges([1, 2, 3, 5, 6, 7]), ['[1-3]', '[5-7]']);
      expect(encodeWeekListRanges(const []), isEmpty);
    });
  });
}

Course _course({
  required String name,
  required int type,
  required List<Arrange> arranges,
}) {
  if (type == 1) {
    return Course.custom(name, '1', '1-24', const [], arranges);
  }
  return Course.spider(
    name,
    'class-id',
    'course-id',
    '1',
    'campus',
    '1-24',
    const [],
    arranges,
  );
}

Arrange _arrange({
  required int weekday,
  required List<int> weeks,
  required List<int> units,
  String location = '',
  List<String> teachers = const [],
}) =>
    Arrange(
      name: null,
      location: location,
      weekday: weekday,
      weekList: List<int>.of(weeks),
      unitList: List<int>.of(units),
      teacherList: List<String>.of(teachers),
      showMode: 0,
      isExperiment: false,
    );
