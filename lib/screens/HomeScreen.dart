import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/attendance_models.dart';
import '../services/app_update_service.dart';
import '../services/attendance_store.dart';
import '../services/pro_service.dart';
import '../theme/app_theme.dart';
import 'app_sidebar.dart';
import 'status_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool isEditMode = false;
  bool _loaded = false;
  bool _started = false;
  bool _listening = false;
  bool _sidebarOpen = false;

  AttendanceStore? _ownedStore;
  ProService? _ownedPro;
  AppUpdateService? _ownedUpdates;
  late AttendanceStore store;
  late ProService pro;
  late AppUpdateService updates;

  AppPalette get _p => AppPalette.of(context);

  final List<String> _weekDays = ["M", "T", "W", "T", "F", "S", "S"];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final inheritedStore = AttendanceStoreScope.maybeOf(context);
      final inheritedPro = ProScope.maybeOf(context);

      if (inheritedStore != null) {
        store = inheritedStore;
      } else {
        store = _ownedStore = AttendanceStore();
        await store.load();
      }

      if (inheritedPro != null) {
        pro = inheritedPro;
      } else {
        pro = _ownedPro = ProService();
        unawaited(pro.init());
      }

      final inheritedUpdates = AppUpdateScope.maybeOf(context);
      if (inheritedUpdates != null) {
        updates = inheritedUpdates;
      } else {
        updates = _ownedUpdates = AppUpdateService();
        unawaited(updates.init());
      }
    } catch (_) {
      store = _ownedStore ??= AttendanceStore();
      await store.load();
      pro = _ownedPro ??= ProService(enableStore: false);
      updates = _ownedUpdates ??= AppUpdateService(enableStore: false);
    }

    store.addListener(_tick);
    pro.addListener(_tick);
    updates.addListener(_tick);
    WidgetsBinding.instance.addObserver(this);
    _listening = true;
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(updates.refresh());
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  Future<void> _onUpdateAction() async {
    final msg = await updates.handleUserTap();
    if (!mounted || msg == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    if (_listening) {
      store.removeListener(_tick);
      pro.removeListener(_tick);
      updates.removeListener(_tick);
      WidgetsBinding.instance.removeObserver(this);
    }
    _ownedStore?.dispose();
    _ownedPro?.dispose();
    _ownedUpdates?.dispose();
    super.dispose();
  }

  List<DateTime?> _buildGrid(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final totalDays = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = firstDay.weekday - 1;
    return [
      ...List.filled(offset, null),
      ...List.generate(
          totalDays, (i) => DateTime(month.year, month.month, i + 1)),
    ];
  }

  void _toggle(DateTime date) {
    if (!isEditMode) return;
    HapticFeedback.selectionClick();
    store.togglePresent(date);
  }

  Future<void> _longPress(DateTime date) async {
    if (!isEditMode) return;
    HapticFeedback.mediumImpact();
    final choice = await showStatusSheet(
      context,
      pro: pro,
      current: store.active.statusOn(date),
    );
    if (choice == null) return;
    await store.setStatus(date, choice.status);
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  void _nextMonth() => setState(() =>
      selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1));

  void _prevMonth() {
    final prev = DateTime(selectedMonth.year, selectedMonth.month - 1);
    final start = store.active.startMonth;
    if (start != null && prev.isBefore(DateTime(start.year, start.month))) {
      return;
    }
    setState(() => selectedMonth = prev);
  }

  String _monthName(int m) => const [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December"
      ][m - 1];

  int get _totalDays =>
      DateUtils.getDaysInMonth(selectedMonth.year, selectedMonth.month);

  int get _presentCount => store.active.attendingInMonth(selectedMonth);

  Color _fillFor(AttendanceStatus? status, AppPalette p) {
    return switch (status) {
      AttendanceStatus.present => p.success,
      AttendanceStatus.late => p.warning,
      AttendanceStatus.excused => p.accent,
      AttendanceStatus.sick => p.danger,
      AttendanceStatus.halfDay => p.halfDay,
      null => p.surface,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_loaded) {
      return Scaffold(
        backgroundColor: p.bg,
        body: Center(child: CircularProgressIndicator(color: p.accent)),
      );
    }

    final grid = _buildGrid(selectedMonth);
    final pct = _totalDays > 0 ? (_presentCount / _totalDays * 100).round() : 0;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: p.bg,
        body: Stack(
          children: [
            Column(
              children: [
                _buildAppBar(p),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildMonthNav(p),
                        _buildWeekdayHeader(p),
                        _buildCalendarGrid(grid, p),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (updates.showBanner)
                        _UpdateBanner(
                          palette: p,
                          downloaded: updates.downloaded,
                          downloading: updates.downloading,
                          onAction: _onUpdateAction,
                          onDismiss: updates.downloaded || updates.downloading
                              ? null
                              : updates.dismissBanner,
                        ),
                      _buildFooter(pct, p),
                    ],
                  ),
                ),
              ],
            ),
            IgnorePointer(
              ignoring: !_sidebarOpen,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: _sidebarOpen ? 1 : 0,
                child: GestureDetector(
                  onTap: () => setState(() => _sidebarOpen = false),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              left: _sidebarOpen ? 0 : -328,
              top: 0,
              bottom: 0,
              width: 320,
              child: Material(
                color: p.surface,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: AppSidebar(
                  store: store,
                  pro: pro,
                  updates: updates,
                  onClose: () => setState(() => _sidebarOpen = false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(AppPalette p) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        left: 20,
        right: 16,
        bottom: 14,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _IconButton(
            palette: p,
            active: _sidebarOpen,
            onTap: () => setState(() => _sidebarOpen = true),
            child: Icon(
              Icons.menu_rounded,
              size: 18,
              color: _sidebarOpen ? p.accent : p.textMid,
            ),
          ),
          const Spacer(),
          _IconButton(
            palette: p,
            active: isEditMode,
            lit: true,
            onTap: () => setState(() => isEditMode = !isEditMode),
            child: Icon(
              isEditMode ? Icons.edit_rounded : Icons.edit_outlined,
              size: 16,
              color: isEditMode ? Colors.white : p.textMid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNav(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
      child: Row(
        children: [
          _NavButton(
            key: const Key('prev_month'),
            onTap: _prevMonth,
            icon: Icons.chevron_left_rounded,
            palette: p,
          ),
          const Spacer(),
          Column(
            children: [
              Text(
                _monthName(selectedMonth.month),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: p.textHigh,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                "${selectedMonth.year}",
                style: TextStyle(
                  fontSize: 12,
                  color: p.textMid,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          _NavButton(
            key: const Key('next_month'),
            onTap: _nextMonth,
            icon: Icons.chevron_right_rounded,
            palette: p,
          ),
        ],
      ),
    );
  }

  Color _unmarkedFill(DateTime date, AppPalette p) {
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    if (weekend) {
      return Color.lerp(p.surfaceAlt, p.accentSoft, 0.42)!;
    }
    return p.surfaceAlt;
  }

  Widget _buildWeekdayHeader(AppPalette p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: _weekDays
            .map(
              (d) => Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.textMid,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid(List<DateTime?> grid, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: grid.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) {
          final date = grid[index];
          if (date == null) return const SizedBox();

          final status = store.active.statusOn(date);
          final isToday = _isToday(date);
          final marked = status != null;
          final fill = _fillFor(status, p);

          Color bgColor;
          Border cellBorder;
          if (status == AttendanceStatus.halfDay) {
            bgColor = _unmarkedFill(date, p);
            cellBorder = Border.all(color: p.halfDay, width: 1.5);
          } else if (marked) {
            bgColor = fill;
            cellBorder = Border.all(color: fill, width: 1);
          } else if (isToday) {
            bgColor = p.accentSoft;
            cellBorder = Border.all(color: p.accent, width: 1.5);
          } else if (isEditMode) {
            // Edit mode: every editable day lights up so it reads as a target.
            bgColor = Color.lerp(_unmarkedFill(date, p), p.accentSoft, 0.55)!;
            cellBorder = Border.all(
              color: p.accent.withValues(alpha: 0.6),
              width: 1.5,
            );
          } else {
            bgColor = _unmarkedFill(date, p);
            cellBorder = Border.all(color: p.border, width: 1.5);
          }

          final List<BoxShadow>? glow;
          if (marked) {
            glow = [
              BoxShadow(
                color: fill.withValues(alpha: isEditMode ? 0.45 : 0.28),
                blurRadius: isEditMode ? 10 : 8,
                offset: const Offset(0, 2),
              ),
            ];
          } else if (isToday || isEditMode) {
            glow = [
              BoxShadow(
                color: p.accent.withValues(alpha: isToday ? 0.18 : 0.14),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ];
          } else {
            glow = null;
          }

          return GestureDetector(
            onTap: () => _toggle(date),
            onLongPress: () => _longPress(date),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: cellBorder,
                boxShadow: glow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  children: [
                    if (status == AttendanceStatus.halfDay)
                      Row(
                        children: [
                          Expanded(child: ColoredBox(color: p.success)),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    if (status == AttendanceStatus.present)
                      Center(
                        child: CustomPaint(
                          size: const Size(13, 13),
                          painter: _CheckPainter(color: Colors.white),
                        ),
                      )
                    else if (status != null &&
                        status != AttendanceStatus.halfDay)
                      Center(
                        child: Text(
                          status.shortLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 5,
                      right: 6,
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: marked && status != AttendanceStatus.halfDay
                              ? Colors.white.withValues(alpha: 0.95)
                              : isToday
                                  ? p.accent
                                  : p.textMid,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter(int pct, AppPalette p) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "PRESENT",
                  style: TextStyle(
                    fontSize: 10,
                    color: p.textMid,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$_presentCount days",
                  style: TextStyle(
                    fontSize: 26,
                    color: p.textHigh,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: p.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$pct% this month",
                  style: TextStyle(
                    fontSize: 13,
                    color: p.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _MiniProgressBar(value: pct / 100, palette: p),
                if (isEditMode) ...[
                  const SizedBox(height: 8),
                  Text(
                    "Hold a day for status",
                    style: TextStyle(
                      fontSize: 10,
                      color: p.textMid,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final AppPalette palette;
  final bool active;
  final VoidCallback onTap;
  final Widget child;

  /// When true, the active state fills with the accent color and glows.
  final bool lit;

  const _IconButton({
    required this.palette,
    required this.active,
    required this.onTap,
    required this.child,
    this.lit = false,
  });

  @override
  Widget build(BuildContext context) {
    final glow = active && lit;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: glow
              ? palette.accent
              : active
                  ? palette.accentSoft
                  : palette.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final AppPalette palette;
  const _NavButton({
    super.key,
    required this.onTap,
    required this.icon,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: palette.textHigh),
      ),
    );
  }
}

class _MiniProgressBar extends StatelessWidget {
  final double value;
  final AppPalette palette;
  const _MiniProgressBar({required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 90,
        height: 6,
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          backgroundColor: palette.border,
          valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({
    required this.palette,
    required this.downloaded,
    required this.downloading,
    required this.onAction,
    this.onDismiss,
  });

  final AppPalette palette;
  final bool downloaded;
  final bool downloading;
  final VoidCallback onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final title = downloaded
        ? 'Update downloaded'
        : downloading
            ? 'Downloading update'
            : 'New version available';
    final subtitle = downloaded
        ? 'Restart to install it.'
        : downloading
            ? 'You can keep using the app.'
            : 'Tap Update to install from Google Play.';
    final action = downloaded
        ? 'Restart'
        : downloading
            ? null
            : 'Update';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            downloaded
                ? Icons.restart_alt_rounded
                : Icons.system_update_alt_rounded,
            size: 18,
            color: palette.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.textHigh,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: palette.textMid,
                  ),
                ),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                action,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: palette.accent,
                ),
              ),
            ),
          if (onDismiss != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Later',
              onPressed: onDismiss,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: palette.textMid,
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final Color color;
  const _CheckPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * 0.15, size.height * 0.5)
      ..lineTo(size.width * 0.42, size.height * 0.76)
      ..lineTo(size.width * 0.85, size.height * 0.24);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}
