import 'package:flutter/material.dart';

import '../services/pro_service.dart';
import '../theme/app_theme.dart';

Future<bool> showProPaywall(
  BuildContext context, {
  required ProService pro,
  required String reason,
}) async {
  final unlocked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PaywallSheet(pro: pro, reason: reason),
  );
  return unlocked == true || pro.isPro;
}

class _PaywallSheet extends StatelessWidget {
  const _PaywallSheet({required this.pro, required this.reason});

  final ProService pro;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: pro,
      builder: (context, _) {
        if (pro.isPro) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop(true);
          });
        }
        return Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          padding: EdgeInsets.fromLTRB(
            22,
            18,
            22,
            18 + MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Unlock Pro',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: p.textHigh,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                reason,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: p.textMid,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'FREE FOREVER',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: p.textLow,
                ),
              ),
              const SizedBox(height: 8),
              _Line(text: 'One calendar, tap to mark present', palette: p),
              _Line(text: 'Monthly total and percentage', palette: p),
              _Line(text: 'Offline, no account', palette: p),
              const SizedBox(height: 16),
              Text(
                'PRO · MONTHLY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: p.accent,
                ),
              ),
              const SizedBox(height: 8),
              _Line(text: 'Unlimited named calendars', palette: p, accent: true),
              _Line(text: 'Late, excused, sick, half-day', palette: p, accent: true),
              _Line(text: 'CSV export and file backup', palette: p, accent: true),
              if (pro.lastError != null) ...[
                const SizedBox(height: 12),
                Text(
                  pro.lastError!,
                  style: TextStyle(fontSize: 12, color: p.danger, height: 1.3),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: pro.purchasePending ? null : () => pro.buy(),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: pro.purchasePending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          pro.priceLabel == null
                              ? 'Subscribe to Pro'
                              : 'Subscribe · ${pro.priceLabel}/mo',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: pro.purchasePending ? null : () => pro.restore(),
                  child: Text(
                    'Restore purchases',
                    style: TextStyle(
                      color: p.textMid,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Billed monthly through Google Play. Cancel anytime in Play Store → Subscriptions. Attendance data stays on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: p.textLow, height: 1.3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.palette, this.accent = false});

  final String text;
  final AppPalette palette;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_rounded,
            size: 16,
            color: accent ? palette.accent : palette.textMid,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: palette.textHigh,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
