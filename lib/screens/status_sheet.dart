import 'package:flutter/material.dart';

import '../models/attendance_models.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'paywall_sheet.dart';

class StatusChoice {
  const StatusChoice(this.status);

  /// `null` clears the day.
  final AttendanceStatus? status;
}

Future<StatusChoice?> showStatusSheet(
  BuildContext context, {
  required ProService pro,
  AttendanceStatus? current,
}) {
  return showModalBottomSheet<StatusChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => _StatusSheet(pro: pro, current: current),
  );
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({required this.pro, this.current});

  final ProService pro;
  final AttendanceStatus? current;

  Future<void> _pick(BuildContext context, AttendanceStatus? status) async {
    if (status != null && status.isProOnly && !pro.isPro) {
      await showProPaywall(
        context,
        pro: pro,
        reason: 'Late, excused, sick, and half-day are part of Pro.',
      );
      if (!pro.isPro) return;
    }
    if (context.mounted) Navigator.pop(context, StatusChoice(status));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: EdgeInsets.fromLTRB(
        8,
        16,
        8,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Day status',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: p.textHigh,
                ),
              ),
            ),
          ),
          _StatusTile(
            palette: p,
            color: p.success,
            label: 'Present',
            selected: current == AttendanceStatus.present,
            onTap: () => _pick(context, AttendanceStatus.present),
          ),
          _StatusTile(
            palette: p,
            color: p.warning,
            label: 'Late',
            locked: !pro.isPro,
            selected: current == AttendanceStatus.late,
            onTap: () => _pick(context, AttendanceStatus.late),
          ),
          _StatusTile(
            palette: p,
            color: p.accent,
            label: 'Excused',
            locked: !pro.isPro,
            selected: current == AttendanceStatus.excused,
            onTap: () => _pick(context, AttendanceStatus.excused),
          ),
          _StatusTile(
            palette: p,
            color: p.danger,
            label: 'Sick',
            locked: !pro.isPro,
            selected: current == AttendanceStatus.sick,
            onTap: () => _pick(context, AttendanceStatus.sick),
          ),
          _StatusTile(
            palette: p,
            color: p.halfDay,
            label: 'Half-day',
            locked: !pro.isPro,
            selected: current == AttendanceStatus.halfDay,
            onTap: () => _pick(context, AttendanceStatus.halfDay),
          ),
          _StatusTile(
            palette: p,
            color: p.textLow,
            label: 'Clear',
            selected: current == null,
            onTap: () => _pick(context, null),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.palette,
    required this.color,
    required this.label,
    required this.onTap,
    this.locked = false,
    this.selected = false,
  });

  final AppPalette palette;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool locked;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: palette.textHigh,
        ),
      ),
      trailing: locked
          ? Icon(Icons.lock_outline_rounded, size: 16, color: palette.textLow)
          : selected
              ? Icon(Icons.check_rounded, color: palette.accent)
              : null,
    );
  }
}
