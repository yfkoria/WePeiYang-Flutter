/// Converts a set of teaching weeks into the range syntax accepted by the
/// custom-course service without filling gaps introduced by schedule changes.
List<String> encodeWeekListRanges(List<int> list) {
  if (list.isEmpty) return const [];
  final weeks = list.toSet().toList()..sort();
  if (weeks.length == 1) return [weeks.single.toString()];

  final isAlternating = List.generate(
    weeks.length - 1,
    (index) => weeks[index + 1] - weeks[index],
  ).every((difference) => difference == 2);
  if (isAlternating) {
    final suffix = weeks.first.isOdd ? '单' : '双';
    return ['[${weeks.first}-${weeks.last}]$suffix'];
  }

  final result = <String>[];
  var start = weeks.first;
  var end = start;
  for (final week in weeks.skip(1)) {
    if (week == end + 1) {
      end = week;
      continue;
    }
    result.add(start == end ? '$start' : '[$start-$end]');
    start = week;
    end = week;
  }
  result.add(start == end ? '$start' : '[$start-$end]');
  return result;
}
