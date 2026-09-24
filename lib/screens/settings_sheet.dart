import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_update_service.dart';
import '../services/attendance_store.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'paywall_sheet.dart';
import 'trackers_sheet.dart';

Future<void> showSettingsSheet(
  BuildContext context, {
  required AttendanceStore store,
  required ProService pro,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _SettingsSheet(store: store, pro: pro),
  );
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.store, required this.pro});

  final AttendanceStore store;
  final ProService pro;

  Future<void> _needPro(BuildContext context, String reason) async {
    if (pro.isPro) return;
    await showProPaywall(context, pro: pro, reason: reason);
  }

  Future<void> _exportCsv(BuildContext context) async {
    await _needPro(
      context,
      'Export a CSV of this calendar with Pro.',
    );
    if (!pro.isPro) return;
    final csv = store.exportCsv();
    final safe = store.active.name.replaceAll(RegExp(r'[^\w]+'), '_');
    try {
      await Share.shareXFiles([
        XFile.fromData(
          utf8.encode(csv),
          mimeType: 'text/csv',
          name: '${safe}_attendance.csv',
        ),
      ]);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share that file.')),
        );
      }
    }
  }

  Future<void> _backup(BuildContext context) async {
    await _needPro(
      context,
      'Save a backup file of every calendar. Uninstall currently wipes history.',
    );
    if (!pro.isPro) return;
    final json = store.exportBackupJson();
    try {
      await Share.shareXFiles([
        XFile.fromData(
          utf8.encode(json),
          mimeType: 'application/json',
          name: 'attendance_flow_backup.json',
        ),
      ]);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not share that file.')),
        );
      }
    }
  }

  Future<void> _restore(BuildContext context) async {
    late final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the file picker.')),
        );
      }
      return;
    }
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read that file.')),
        );
      }
      return;
    }
    final raw = utf8.decode(file.bytes!);
    try {
      await store.restoreBackupJson(raw);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not restore that backup.')),
        );
      }
    }
  }

  Future<void> _restorePurchases(BuildContext context) async {
    final err = await pro.restore();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (pro.isPro
                  ? 'Pro restored.'
                  : 'No Pro purchase found on this Google account.'),
        ),
      ),
    );
  }

  Future<void> _onAppUpdate(BuildContext context) async {
    final updates = AppUpdateScope.maybeOf(context);
    if (updates == null) return;
    final msg = await updates.handleUserTap();
    if (!context.mounted || msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final updates = AppUpdateScope.maybeOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        store,
        pro,
        if (updates != null) updates,
      ]),
      builder: (context, _) {
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
                child: Row(
                  children: [
                    Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: p.textHigh,
                      ),
                    ),
                    const Spacer(),
                    if (pro.isPro)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: p.accentSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: p.accent,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _Row(
                palette: p,
                icon: Icons.calendar_month_outlined,
                label: 'Calendars',
                onTap: () => showTrackersSheet(context, store: store, pro: pro),
              ),
              _Row(
                palette: p,
                icon: Icons.ios_share_rounded,
                label: 'Export CSV',
                locked: !pro.isPro,
                onTap: () => _exportCsv(context),
              ),
              _Row(
                palette: p,
                icon: Icons.file_upload_outlined,
                label: 'Backup to file',
                locked: !pro.isPro,
                onTap: () => _backup(context),
              ),
              _Row(
                palette: p,
                icon: Icons.file_download_outlined,
                label: 'Restore from file',
                onTap: () => _restore(context),
              ),
              _Row(
                palette: p,
                icon: Icons.restore_rounded,
                label: 'Restore purchases',
                onTap: () => _restorePurchases(context),
              ),
              if (updates != null)
                _Row(
                  palette: p,
                  icon: updates.downloaded
                      ? Icons.restart_alt_rounded
                      : Icons.system_update_alt_rounded,
                  label: updates.actionLabel,
                  onTap: () => _onAppUpdate(context),
                ),
              if (!pro.isPro)
                _Row(
                  palette: p,
                  icon: Icons.workspace_premium_outlined,
                  label: 'Unlock Pro',
                  onTap: () => showProPaywall(
                    context,
                    pro: pro,
                    reason:
                        'Unlimited calendars, extra statuses, export, and backup with a monthly Pro subscription.',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.locked = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: palette.textMid),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: palette.textHigh,
        ),
      ),
      trailing: locked
          ? Icon(Icons.lock_outline_rounded, size: 16, color: palette.textLow)
          : Icon(Icons.chevron_right_rounded, color: palette.textLow),
    );
  }
}
