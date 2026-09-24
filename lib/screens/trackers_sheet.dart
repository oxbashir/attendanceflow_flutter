import 'package:flutter/material.dart';

import '../services/attendance_store.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'paywall_sheet.dart';

Future<void> showTrackersSheet(
  BuildContext context, {
  required AttendanceStore store,
  required ProService pro,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _TrackersSheet(store: store, pro: pro),
  );
}

class _TrackersSheet extends StatelessWidget {
  const _TrackersSheet({required this.store, required this.pro});

  final AttendanceStore store;
  final ProService pro;

  Future<void> _add(BuildContext context) async {
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

  Future<void> _rename(BuildContext context, String id, String current) async {
    final name =
        await promptTrackerName(context, title: 'Rename', initial: current);
    if (name == null) return;
    await store.renameTracker(id, name);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([store, pro]),
      builder: (context, _) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: EdgeInsets.fromLTRB(
            8,
            16,
            8,
            10 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: p.shadow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
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
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Calendars',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: p.textHigh,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () => _add(context),
                      icon: Icon(
                        pro.isPro
                            ? Icons.add_rounded
                            : Icons.lock_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in store.trackers)
                      ListTile(
                        onTap: () {
                          store.select(t.id);
                          Navigator.pop(context);
                        },
                        leading: Icon(
                          t.id == store.activeId
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: t.id == store.activeId ? p.accent : p.textLow,
                        ),
                        title: Text(
                          t.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: p.textHigh,
                          ),
                        ),
                        subtitle: Text(
                          '${t.days.length} marked days',
                          style: TextStyle(color: p.textMid, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename',
                              onPressed: () => _rename(context, t.id, t.name),
                              icon: Icon(Icons.edit_outlined,
                                  color: p.textMid, size: 18),
                            ),
                            if (store.trackers.length > 1)
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () => store.deleteTracker(t.id),
                                icon: Icon(Icons.delete_outline,
                                    color: p.danger, size: 18),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (!pro.isPro)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Free includes one calendar. Subscribe to Pro to add Work, Gym, Class, and more.',
                    style:
                        TextStyle(fontSize: 12, color: p.textMid, height: 1.35),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Future<String?> promptTrackerName(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  final controller = TextEditingController(text: initial ?? '');
  final p = AppPalette.of(context);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: p.surface,
      title: Text(title, style: TextStyle(color: p.textHigh)),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Work, Gym, Class…'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
