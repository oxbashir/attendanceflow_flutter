import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/app_update_service.dart';
import '../services/attendance_store.dart';
import '../services/auth_service.dart';
import '../services/pro_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'account_section.dart';
import 'export_sheet.dart';
import 'paywall_sheet.dart';

Future<void> openSettings(
  BuildContext context, {
  required AttendanceStore store,
  required ProService pro,
  required AppUpdateService updates,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(
        store: store,
        pro: pro,
        updates: updates,
      ),
    ),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.pro,
    required this.updates,
  });

  final AttendanceStore store;
  final ProService pro;
  final AppUpdateService updates;

  Future<void> _needPro(BuildContext context, String reason) async {
    if (pro.isPro) return;
    await showProPaywall(context, pro: pro, reason: reason);
  }

  Future<void> _exportCsv(BuildContext context) async {
    await _needPro(context, 'Export a CSV of this calendar with Pro.');
    if (!pro.isPro) return;
    if (!context.mounted) return;
    final safe = store.active.name.replaceAll(RegExp(r'[^\w]+'), '_');
    await exportUserFile(
      context,
      title: 'Export CSV',
      fileName: '${safe}_attendance.csv',
      mimeType: 'text/csv',
      bytes: utf8Bytes(store.exportCsv()),
      allowedExtensions: const ['csv'],
    );
  }

  Future<void> _backup(BuildContext context) async {
    await _needPro(
      context,
      'Save a backup file of every calendar. Uninstall currently wipes history.',
    );
    if (!pro.isPro) return;
    if (!context.mounted) return;
    await exportUserFile(
      context,
      title: 'Save backup',
      fileName: 'attendance_flow_backup.json',
      mimeType: 'application/json',
      bytes: utf8Bytes(store.exportBackupJson()),
      allowedExtensions: const ['json'],
    );
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
    final auth = AuthScope.maybeOf(context);
    final sync = SyncScope.maybeOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        store,
        pro,
        updates,
        if (auth != null) auth,
        if (sync != null) sync,
      ]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: p.textHigh),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              'Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: p.textHigh,
                letterSpacing: -0.3,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _SectionLabel(text: 'Appearance', palette: p),
              const SizedBox(height: 8),
              if (theme != null)
                _ThemeSwitch(
                  palette: p,
                  isDark: isDark,
                  onLight: () => theme.setMode(ThemeMode.light),
                  onDark: () => theme.setMode(ThemeMode.dark),
                ),
              const SizedBox(height: 22),
              _SectionLabel(text: 'Files', palette: p),
              const SizedBox(height: 8),
              _GroupedCard(
                palette: p,
                children: [
                  _GroupTile(
                    palette: p,
                    icon: Icons.ios_share_rounded,
                    label: 'Export CSV',
                    locked: !pro.isPro,
                    onTap: () => _exportCsv(context),
                  ),
                  _GroupTile(
                    palette: p,
                    icon: Icons.file_upload_outlined,
                    label: 'Save backup',
                    locked: !pro.isPro,
                    onTap: () => _backup(context),
                  ),
                  _GroupTile(
                    palette: p,
                    icon: Icons.file_download_outlined,
                    label: 'Restore backup',
                    onTap: () => _restore(context),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (auth != null)
                AccountSection(
                  palette: p,
                  auth: auth,
                  pro: pro,
                  sync: sync,
                  sectionLabel: (text) => _SectionLabel(text: text, palette: p),
                ),
              _SectionLabel(text: 'App', palette: p),
              const SizedBox(height: 8),
              _GroupedCard(
                palette: p,
                children: [
                  _GroupTile(
                    palette: p,
                    icon: updates.downloaded
                        ? Icons.restart_alt_rounded
                        : Icons.system_update_alt_rounded,
                    label: updates.actionLabel,
                    accent: updates.updateAvailable || updates.downloaded,
                    onTap: () => _onAppUpdate(context),
                  ),
                  if (!pro.isPro)
                    _GroupTile(
                      palette: p,
                      icon: Icons.restore_rounded,
                      label: 'Restore purchases',
                      onTap: () => _restorePurchases(context),
                    ),
                ],
              ),
            ],
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
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
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
          color: selected ? palette.surfaceAlt : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? (icon == CupertinoIcons.sun_max_fill
                      ? palette.gold
                      : palette.accent)
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

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.palette, required this.children});

  final AppPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 40,
                color: palette.border.withValues(alpha: 0.45),
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
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
    return Material(
      color: accent ? palette.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
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
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.chevron_right_rounded,
                size: 16,
                color: palette.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
