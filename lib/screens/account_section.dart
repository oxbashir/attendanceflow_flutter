import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/account_config.dart';
import '../services/auth_service.dart';
import '../services/pro_service.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';

enum _AccountAction { manage, sync, signOut, delete }

/// Compact account card for the sidebar. Hidden for free users who have
/// never signed in. Extra actions live in a menu so the drawer stays short.
class AccountSection extends StatelessWidget {
  const AccountSection({
    super.key,
    required this.palette,
    required this.auth,
    required this.pro,
    required this.sync,
    required this.sectionLabel,
  });

  final AppPalette palette;
  final AuthService auth;
  final ProService pro;
  final SyncService? sync;
  final Widget Function(String text) sectionLabel;

  static Future<void> openManageSubscription(BuildContext context) async {
    final ok = await launchUrl(
      Uri.parse(AccountConfig.manageSubscriptionUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Google Play → Payments & subscriptions to manage Pro.',
          ),
        ),
      );
    }
  }

  Future<void> _signIn(BuildContext context) async {
    final err = await auth.signInWithGoogle();
    if (err == null) await pro.refreshEntitlement();
    if (!context.mounted) return;
    if (err == AuthService.cancelledMessage) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Signed in.')),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your calendars stay on this phone. Pro turns off until you sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await auth.signOut();
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your account and every calendar stored in the cloud. '
          'Calendars on this phone are kept.\n\n'
          'Your Pro subscription is billed by Google Play and is NOT cancelled '
          'by this. Cancel it in Google Play → Payments & subscriptions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: palette.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await auth.deleteAccount();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err ?? 'Account deleted.')),
    );
  }

  Future<void> _syncNow(BuildContext context) async {
    final s = sync;
    if (s == null) return;
    await s.syncNow();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.lastError ?? 'Calendars are up to date.')),
    );
  }

  Future<void> _onAction(BuildContext context, _AccountAction action) async {
    switch (action) {
      case _AccountAction.manage:
        await openManageSubscription(context);
      case _AccountAction.sync:
        await _syncNow(context);
      case _AccountAction.signOut:
        await _signOut(context);
      case _AccountAction.delete:
        await _deleteAccount(context);
    }
  }

  String _subscriptionLine() {
    final e = pro.entitlement;
    if (!pro.isPro) return 'Free';
    if (e?.expiresAt == null) return 'Pro';
    final d = e!.expiresAt!.toLocal();
    final date = '${d.day}/${d.month}/${d.year}';
    return e.autoRenewing ? 'Pro · renews $date' : 'Pro · ends $date';
  }

  PopupMenuItem<_AccountAction> _item({
    required _AccountAction value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final ink = color ?? palette.textHigh;
    return PopupMenuItem<_AccountAction>(
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
    if (!auth.enabled) return const SizedBox.shrink();

    if (!auth.isSignedIn) {
      if (!pro.isPro) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionLabel('Account'),
            const SizedBox(height: 8),
            Material(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: auth.busy ? null : () => _signIn(context),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      if (auth.busy)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.accent,
                          ),
                        )
                      else
                        Icon(
                          Icons.cloud_outlined,
                          size: 18,
                          color: palette.textMid,
                        ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Back up calendars',
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
            ),
          ],
        ),
      );
    }

    final user = auth.user!;
    final name = user.displayName ?? user.email ?? 'Google account';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionLabel('Account'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _Avatar(palette: palette, user: user),
                const SizedBox(width: 12),
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
                        _subscriptionLine(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: pro.isPro ? palette.success : palette.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_AccountAction>(
                  tooltip: 'Account',
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
                  constraints: const BoxConstraints(minWidth: 168),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    size: 18,
                    color: palette.textMid,
                  ),
                  onSelected: (action) => _onAction(context, action),
                  itemBuilder: (context) => [
                    _item(
                      value: _AccountAction.manage,
                      icon: Icons.credit_card_outlined,
                      label: 'Manage plan',
                    ),
                    if (pro.isPro && sync != null)
                      _item(
                        value: _AccountAction.sync,
                        icon: Icons.sync_rounded,
                        label: sync!.syncing ? 'Syncing…' : 'Sync now',
                      ),
                    _item(
                      value: _AccountAction.signOut,
                      icon: Icons.logout_rounded,
                      label: 'Sign out',
                    ),
                    _item(
                      value: _AccountAction.delete,
                      icon: Icons.delete_outline,
                      label: 'Delete account',
                      color: palette.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.palette, required this.user});

  final AppPalette palette;
  final AccountUser user;

  @override
  Widget build(BuildContext context) {
    final initial = (user.displayName ?? user.email ?? '?').trim();
    final letter = initial.isEmpty ? '?' : initial[0].toUpperCase();
    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: user.photoUrl != null
          ? Image.network(
              user.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letter(letter),
            )
          : _letter(letter),
    );
  }

  Widget _letter(String letter) => Center(
        child: Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: palette.accent,
          ),
        ),
      );
}
