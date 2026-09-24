import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_update_service.dart';
import '../services/attendance_store.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'paywall_sheet.dart';
import 'trackers_sheet.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.store,
    required this.pro,
    required this.updates,
    this.onClose,
  });

  final AttendanceStore store;
  final ProService pro;
  final AppUpdateService updates;
  final VoidCallback? onClose;

  Future<void> _needPro(BuildContext context, String reason) async {
    if (pro.isPro) return;
    await showProPaywall(context, pro: pro, reason: reason);
  }

  Future<void> _addCalendar(BuildContext context) async {
    if (!pro.isPro && store.trackers.isNotEmpty) {
      await showProPaywall(
        context,
        pro: pro,
        reason:
            'A second calendar is a Pro feature — Work, Gym, Class, and more.',
      );
      if (!pro.isPro) return;
    }
    if (!context.mounted) return;
    final name = await promptTrackerName(context, title: 'New calendar');
    if (name == null || name.trim().isEmpty) return;
    await store.addTracker(name, isPro: pro.isPro);
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
    try {
      await Share.shareXFiles([
        XFile.fromData(
          utf8.encode(store.exportBackupJson()),
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
    try {
      await store.restoreBackupJson(utf8.decode(file.bytes!));
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
    final msg = await updates.handleUserTap();
    if (!context.mounted || msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = ThemeScope.maybeOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([store, pro, updates]),
      builder: (context, _) {
        return ColoredBox(
          color: p.surface,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: p.accentSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          CupertinoIcons.checkmark_seal_fill,
                          size: 20,
                          color: p.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Attendance Flow',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: p.textHigh,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'Private · on this device',
                              style: TextStyle(
                                fontSize: 11,
                                color: p.textMid,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
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
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: p.accent,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      if (pro.isPro && onClose != null)
                        const SizedBox(width: 16),
                      if (onClose != null)
                        Tooltip(
                          message: 'Close',
                          child: Material(
                            color: p.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: onClose,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: p.border, width: 1.5),
                                ),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  size: 18,
                                  color: p.textHigh,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    children: [
                      _SectionLabel(text: 'Calendars', palette: p),
                      const SizedBox(height: 8),
                      for (final t in store.trackers) ...[
                        _CalendarTile(
                          palette: p,
                          name: t.name,
                          days: t.days.length,
                          selected: t.id == store.activeId,
                          onTap: () {
                            store.select(t.id);
                            onClose?.call();
                          },
                          onRename: () async {
                            final name = await promptTrackerName(
                              context,
                              title: 'Rename',
                              initial: t.name,
                            );
                            if (name == null) return;
                            await store.renameTracker(t.id, name);
                          },
                          onDelete: store.trackers.length > 1
                              ? () => store.deleteTracker(t.id)
                              : null,
                        ),
                        const SizedBox(height: 8),
                      ],
                      _AddRow(
                        palette: p,
                        locked: !pro.isPro,
                        onTap: () => _addCalendar(context),
                      ),
                      const SizedBox(height: 22),
                      _SectionLabel(text: 'Appearance', palette: p),
                      const SizedBox(height: 10),
                      if (theme != null)
                        _ThemeSwitch(
                          palette: p,
                          isDark: isDark,
                          onLight: () => theme.setMode(ThemeMode.light),
                          onDark: () => theme.setMode(ThemeMode.dark),
                        ),
                      const SizedBox(height: 22),
                      _SectionLabel(text: 'Data', palette: p),
                      const SizedBox(height: 8),
                      _ActionRow(
                        palette: p,
                        icon: Icons.ios_share_rounded,
                        label: 'Export CSV',
                        locked: !pro.isPro,
                        onTap: () => _exportCsv(context),
                      ),
                      _ActionRow(
                        palette: p,
                        icon: Icons.file_upload_outlined,
                        label: 'Backup to file',
                        locked: !pro.isPro,
                        onTap: () => _backup(context),
                      ),
                      _ActionRow(
                        palette: p,
                        icon: Icons.file_download_outlined,
                        label: 'Restore from file',
                        onTap: () => _restore(context),
                      ),
                      const SizedBox(height: 22),
                      _SectionLabel(text: 'Pro', palette: p),
                      const SizedBox(height: 8),
                      if (!pro.isPro)
                        _ActionRow(
                          palette: p,
                          icon: Icons.workspace_premium_outlined,
                          label: 'Unlock Pro',
                          accent: true,
                          onTap: () => showProPaywall(
                            context,
                            pro: pro,
                            reason:
                                'Unlimited calendars, extra statuses, export, and backup with a monthly Pro subscription.',
                          ),
                        ),
                      _ActionRow(
                        palette: p,
                        icon: Icons.restore_rounded,
                        label: 'Restore purchases',
                        onTap: () => _restorePurchases(context),
                      ),
                      const SizedBox(height: 22),
                      _SectionLabel(text: 'App', palette: p),
                      const SizedBox(height: 8),
                      _ActionRow(
                        palette: p,
                        icon: updates.downloaded
                            ? Icons.restart_alt_rounded
                            : Icons.system_update_alt_rounded,
                        label: updates.actionLabel,
                        accent:
                            updates.updateAvailable || updates.downloaded,
                        onTap: () => _onAppUpdate(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: palette.textLow,
      ),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({
    required this.palette,
    required this.name,
    required this.days,
    required this.selected,
    required this.onTap,
    required this.onRename,
    this.onDelete,
  });

  final AppPalette palette;
  final String name;
  final int days;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? palette.accentSoft : palette.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent.withValues(alpha: 0.35) : palette.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 18,
                color: selected ? palette.accent : palette.textLow,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: palette.textHigh,
                      ),
                    ),
                    Text(
                      '$days marked',
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textMid,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Rename',
                onPressed: onRename,
                icon: Icon(Icons.edit_outlined, size: 16, color: palette.textMid),
              ),
              if (onDelete != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Delete',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, size: 16, color: palette.danger),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.palette,
    required this.onTap,
    required this.locked,
  });

  final AppPalette palette;
  final VoidCallback onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_outline_rounded : Icons.add_rounded,
                size: 18,
                color: palette.accent,
              ),
              const SizedBox(width: 10),
              Text(
                'Add calendar',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: palette.textHigh,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSwitch extends StatelessWidget {
  const _ThemeSwitch({
    required this.palette,
    required this.isDark,
    required this.onLight,
    required this.onDark,
  });

  final AppPalette palette;
  final bool isDark;
  final VoidCallback onLight;
  final VoidCallback onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ThemeChip(
              palette: palette,
              selected: !isDark,
              icon: CupertinoIcons.sun_max_fill,
              label: 'Light',
              onTap: onLight,
            ),
          ),
          Expanded(
            child: _ThemeChip(
              palette: palette,
              selected: isDark,
              icon: CupertinoIcons.moon_fill,
              label: 'Dark',
              onTap: onDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  const _ThemeChip({
    required this.palette,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: selected ? Border.all(color: palette.border) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? (icon == CupertinoIcons.sun_max_fill
                      ? const Color(0xFFE8A017)
                      : const Color(0xFF6B93FF))
                  : palette.textMid,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected ? palette.textHigh : palette.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.locked = false,
    this.accent = false,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool locked;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: accent ? palette.accentSoft : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: accent ? palette.accent : palette.textMid,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: palette.textHigh,
                    ),
                  ),
                ),
                Icon(
                  locked ? Icons.lock_outline_rounded : Icons.chevron_right_rounded,
                  size: 16,
                  color: palette.textLow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
