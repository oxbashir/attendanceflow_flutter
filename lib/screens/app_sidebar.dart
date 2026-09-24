import 'package:flutter/material.dart';

import '../services/app_update_service.dart';
import '../services/attendance_store.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'paywall_sheet.dart';
import 'settings_sheet.dart';
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

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([store, pro]),
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
                      Expanded(
                        child: Text(
                          'Attendance Flow',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: p.textHigh,
                            letterSpacing: -0.3,
                          ),
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
                        const SizedBox(width: 10),
                      if (onClose != null)
                        Tooltip(
                          message: 'Close',
                          child: Material(
                            color: p.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: onClose,
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 36,
                                height: 36,
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
                        onTap: () => _addCalendar(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      if (!pro.isPro) ...[
                        _UpgradeCard(
                          palette: p,
                          onTap: () => showProPaywall(
                            context,
                            pro: pro,
                            reason:
                                'Unlimited calendars, extra statuses, export, and backup with a monthly Pro subscription.',
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _SettingsRow(
                        palette: p,
                        onTap: () => openSettings(
                          context,
                          store: store,
                          pro: pro,
                          updates: updates,
                        ),
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
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? palette.accent : palette.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
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
              _TileMenu(
                palette: palette,
                onRename: onRename,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _TileAction { rename, delete }

class _TileMenu extends StatelessWidget {
  const _TileMenu({
    required this.palette,
    required this.onRename,
    this.onDelete,
  });

  final AppPalette palette;
  final VoidCallback onRename;
  final VoidCallback? onDelete;

  PopupMenuItem<_TileAction> _item({
    required _TileAction value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final ink = color ?? palette.textHigh;
    return PopupMenuItem<_TileAction>(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ink),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TileAction>(
      tooltip: 'More',
      padding: EdgeInsets.zero,
      splashRadius: 18,
      position: PopupMenuPosition.under,
      color: palette.surface,
      elevation: 6,
      shadowColor: palette.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      constraints: const BoxConstraints(minWidth: 120),
      icon: Icon(Icons.more_vert_rounded, size: 18, color: palette.textMid),
      onSelected: (action) {
        switch (action) {
          case _TileAction.rename:
            onRename();
          case _TileAction.delete:
            onDelete?.call();
        }
      },
      itemBuilder: (context) => [
        _item(
          value: _TileAction.rename,
          icon: Icons.edit_outlined,
          label: 'Rename',
        ),
        if (onDelete != null)
          _item(
            value: _TileAction.delete,
            icon: Icons.delete_outline,
            label: 'Delete',
            color: palette.danger,
          ),
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({
    required this.palette,
    required this.onTap,
  });

  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 48,
          child: Center(
            child: Icon(
              Icons.add_rounded,
              size: 22,
              color: palette.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.palette, required this.onTap});

  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.goldSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: palette.gold.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: 18,
                  color: palette.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Upgrade to Pro',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: palette.textHigh,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: palette.gold,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.palette, required this.onTap});

  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.settings_outlined, size: 18, color: palette.textMid),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Settings',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: palette.textHigh,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
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
