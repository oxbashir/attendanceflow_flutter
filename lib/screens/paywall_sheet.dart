import 'package:flutter/material.dart';

import '../services/auth_service.dart';
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

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({required this.pro, required this.reason});

  final ProService pro;
  final String reason;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  ProService get pro => widget.pro;
  bool _checkingAccount = false;
  String? _signInError;

  Future<void> _upgrade(AuthService? auth) async {
    setState(() {
      _signInError = null;
      _checkingAccount = true;
    });
    if (pro.requiresSignIn && auth != null) {
      final err = await auth.signInWithGoogle();
      if (err == null) {
        await pro.refreshEntitlement();
      }
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _checkingAccount = false;
          _signInError = err == AuthService.cancelledMessage ? null : err;
        });
        return;
      }
      if (pro.isPro) {
        setState(() => _checkingAccount = false);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _checkingAccount = false);
    await pro.buy();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final auth = AuthScope.maybeOf(context);
    return ListenableBuilder(
      listenable: auth == null ? pro : Listenable.merge([pro, auth]),
      builder: (context, _) {
        if (pro.isPro) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.of(context).pop(true);
          });
        }
        final busy =
            pro.purchasePending || _checkingAccount || (auth?.busy ?? false);
        final reason = widget.reason;
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
                'Upgrade to Pro',
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
              _Line(
                  text: 'Unlimited named calendars', palette: p, accent: true),
              _Line(
                  text: 'Late, excused, sick, half-day',
                  palette: p,
                  accent: true),
              _Line(
                  text: 'CSV export and file backup', palette: p, accent: true),
              if (auth != null && auth.enabled)
                _Line(
                  text: 'Calendars backed up to your Google account',
                  palette: p,
                  accent: true,
                ),
              if ((_signInError ?? pro.lastError) != null) ...[
                const SizedBox(height: 12),
                Text(
                  _signInError ?? pro.lastError!,
                  style: TextStyle(fontSize: 12, color: p.danger, height: 1.3),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : () => _upgrade(auth),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: busy
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
                  onPressed: busy ? null : () => pro.restore(),
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
