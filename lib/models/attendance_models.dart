enum AttendanceStatus {
  present,
  late,
  excused,
  sick,
  halfDay;

  bool get isProOnly => this != AttendanceStatus.present;

  bool get countsAsAttending =>
      this == AttendanceStatus.present ||
      this == AttendanceStatus.late ||
      this == AttendanceStatus.halfDay;

  String get label => switch (this) {
        AttendanceStatus.present => 'Present',
        AttendanceStatus.late => 'Late',
        AttendanceStatus.excused => 'Excused',
        AttendanceStatus.sick => 'Sick',
        AttendanceStatus.halfDay => 'Half-day',
      };

  String get shortLabel => switch (this) {
        AttendanceStatus.present => '',
        AttendanceStatus.late => 'L',
        AttendanceStatus.excused => 'E',
        AttendanceStatus.sick => 'S',
        AttendanceStatus.halfDay => '½',
      };

  static AttendanceStatus? fromStorage(String raw) {
    return switch (raw) {
      'present' => AttendanceStatus.present,
      'late' => AttendanceStatus.late,
      'excused' => AttendanceStatus.excused,
      'sick' => AttendanceStatus.sick,
      'halfDay' => AttendanceStatus.halfDay,
      _ => null,
    };
  }

  String get storage => name;
}

class Tracker {
  Tracker({
    required this.id,
    required this.name,
    this.startMonth,
    Map<String, AttendanceStatus>? days,
    this.updatedAt,
  }) : days = days ?? {};

  final String id;
  String name;
  DateTime? startMonth;
  final Map<String, AttendanceStatus> days;

  /// Last local mutation, in UTC. Used to pick a winner when the same
  /// calendar was edited on two devices.
  DateTime? updatedAt;

  void touch() => updatedAt = DateTime.now().toUtc();

  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  AttendanceStatus? statusOn(DateTime d) =>
      days[dayKey(DateTime(d.year, d.month, d.day))];

  int attendingInMonth(DateTime month) {
    var n = 0;
    days.forEach((key, status) {
      if (!status.countsAsAttending) return;
      final parts = key.split('-');
      if (parts.length != 3) return;
      if (int.parse(parts[0]) == month.year &&
          int.parse(parts[1]) == month.month) {
        n++;
      }
    });
    return n;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startMonth': startMonth == null
            ? null
            : '${startMonth!.year}-${startMonth!.month}',
        'days': days.map((k, v) => MapEntry(k, v.storage)),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  factory Tracker.fromJson(Map<String, dynamic> json) {
    DateTime? start;
    final sm = json['startMonth'];
    if (sm is String && sm.contains('-')) {
      final p = sm.split('-');
      start = DateTime(int.parse(p[0]), int.parse(p[1]));
    }
    DateTime? updated;
    final rawUpdated = json['updatedAt'];
    if (rawUpdated is String) updated = DateTime.tryParse(rawUpdated)?.toUtc();
    final rawDays = json['days'];
    final days = <String, AttendanceStatus>{};
    if (rawDays is Map) {
      rawDays.forEach((key, value) {
        final status = AttendanceStatus.fromStorage(value.toString());
        if (status != null) days[key.toString()] = status;
      });
    }
    return Tracker(
      id: json['id'] as String? ?? 'default',
      name: json['name'] as String? ?? 'Attendance',
      startMonth: start,
      days: days,
      updatedAt: updated,
    );
  }
}
