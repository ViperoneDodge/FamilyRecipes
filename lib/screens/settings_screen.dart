import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../main.dart';
import '../services/support_service.dart';
import '../services/sync_service.dart' show cloudErrorMessage;
import '../theme.dart';
import '../version.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'family_screen.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final s = appState.session;
        final scheme = Theme.of(context).colorScheme;
        return TableclothBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: Text(tr('settings.title'))),
            body: NotebookPage(
              child: ListView(padding: const EdgeInsets.only(top: 0, right: 4), children: [
                _header(context, tr('settings.account')),
                ListTile(
                  leading: Icon(appState.isCloud ? Icons.cloud : Icons.phone_android),
                  title: Text(s?.displayName ?? ''),
                  subtitle: Text([
                    if (appState.isCloud && s?.email != null && s!.email != s.displayName) s.email!,
                    appState.isCloud ? tr('settings.accountCloud') : tr('settings.accountLocal'),
                  ].join('\n')),
                ),
                if (!appState.isCloud && appState.auth.cloudAvailable)
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: Text(tr('upgrade.button')),
                    subtitle: Text(tr('upgrade.settingsInfo')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const LoginScreen(upgrade: true))),
                  ),
                _header(context, tr('settings.language')),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(appState.langPref == null
                      ? '${tr('settings.langAuto')} (${L10n.names[L10n.code]})'
                      : (L10n.names[appState.langPref] ?? appState.langPref!)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _chooseLanguage(context),
                ),
                ..._appearance(context),
                _header(context, tr('settings.notifications')),
                const _NotifyStatus(),
                if (appState.isCloud)
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: Text(tr('settings.groupAlerts')),
                    subtitle: Text(tr('settings.groupAlertsInfo')),
                    value: appState.groupAlerts,
                    onChanged: (on) => appState.setGroupAlerts(on),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(tr('settings.alertsNeedCloud'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: Text(tr('settings.testNow')),
                  subtitle: Text(tr('settings.testNowInfo')),
                  onTap: () async {
                    await appState.notifications.requestPermission();
                    await appState.notifications.showTest();
                  },
                ),
                if (appState.isCloud)
                  ListTile(
                    leading: Icon(
                      appState.push.registered ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                      color: appState.push.registered ? Colors.green.shade700 : Colors.orange.shade800,
                    ),
                    title: Text(appState.push.registered ? tr('settings.pushOk') : tr('settings.pushNo')),
                    subtitle: Text(appState.push.registered ? tr('settings.pushOkInfo') : tr('settings.pushNoInfo')),
                    onTap: () async {
                      if (!appState.push.registered) {
                        await appState.startPush();
                        if (context.mounted && !appState.push.registered) {
                          showSnack(context, tr('settings.pushFailed'));
                        }
                        return;
                      }
                      Clipboard.setData(ClipboardData(text: appState.push.token!));
                      showSnack(context, tr('settings.pushCopied'));
                    },
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(tr('settings.batteryHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
                _header(context, tr('settings.groups')),
                if (!appState.isCloud)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      appState.auth.cloudAvailable ? tr('settings.groupsNeedCloud') : tr('family.cloudOff'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  ..._familySection(context),
                _header(context, tr('support.title')),
                if (appState.isAdmin)
                  ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined, color: scheme.primary),
                    title: Text(tr('admin.title')),
                    subtitle: Text(tr('admin.subtitle')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminScreen())),
                  ),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: Text(tr('bug.title')),
                  subtitle: Text(tr('bug.subtitle')),
                  onTap: () => _bugReport(context),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(tr('privacy.title')),
                  subtitle: Text(tr('privacy.subtitle')),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () async {
                    final ok = await SupportService.openPrivacy();
                    if (!ok && context.mounted) showSnack(context, SupportService.privacyUrl);
                  },
                ),
                if (appState.isCloud)
                  ListTile(
                    leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                    title: Text(tr('account.delete'), style: TextStyle(color: scheme.error)),
                    subtitle: Text(tr('account.deleteInfo')),
                    onTap: () => _deleteAccount(context),
                  ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(tr('settings.logout')),
                  subtitle: Text(tr('settings.logoutInfo')),
                  onTap: () async {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    await appState.logout();
                  },
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text('FamilyRecipes $appVersion', style: TextStyle(fontSize: 12, color: scheme.outline)),
                ),
                const SizedBox(height: 14),
                Center(
                  child: Image.asset('assets/gian_trip_logo.png',
                      width: 96, height: 96, filterQuality: FilterQuality.medium),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text('© 2026 Gian Trip Apps', style: TextStyle(fontSize: 12, color: scheme.outline)),
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _bugReport(BuildContext context) async {
    final name = TextEditingController(text: appState.session?.displayName ?? '');
    final msg = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('bug.title')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('bug.name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: msg,
              maxLines: 6,
              minLines: 4,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: tr('bug.message'), alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            Text(tr('bug.info'), style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send),
            label: Text(tr('bug.send')),
          ),
        ],
      ),
    );
    if (send != true || msg.text.trim().isEmpty) return;
    final device = await SupportService.deviceDescription();
    final body = '${msg.text.trim()}\n\n'
        '-----\n'
        '${tr('bug.name')}: ${name.text.trim()}\n'
        'App: FamilyRecipes $appVersion\n'
        '${appState.isCloud ? 'Account online' : 'Account locale'} · ${L10n.code}\n'
        '$device\n';
    final ok = await SupportService.openEmail(subject: 'FamilyRecipes $appVersion - ${tr('bug.title')}', body: body);
    if (!ok && context.mounted) {
      showSnack(context, tr('bug.noMail', {'email': SupportService.email}));
    }
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('account.deleteTitle')),
        content: Text(tr('account.deleteBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('common.delete')),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final complete = await appState.deleteCloudAccount();
      nav.popUntil((r) => r.isFirst);
      messenger.showSnackBar(SnackBar(content: Text(complete ? tr('account.deleted') : tr('account.relogin'))));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(cloudErrorMessage(e))));
    }
  }

  List<Widget> _appearance(BuildContext context) {
    final t = appState.theme;
    void save({ThemeMode? mode, int? palette, PaperStyle? paper, bool? tablecloth}) {
      appState.updateTheme(ThemeSettings(
        mode: mode ?? t.mode,
        palette: palette ?? t.palette,
        paper: paper ?? t.paper,
        tablecloth: tablecloth ?? t.tablecloth,
      ));
    }

    return [
      _header(context, tr('settings.appearance')),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(tr('theme.light'))),
            ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(tr('theme.dark'))),
            ButtonSegment(
                value: ThemeMode.system, icon: const Icon(Icons.brightness_auto), label: Text(tr('theme.auto'))),
          ],
          selected: {t.mode},
          onSelectionChanged: (sel) => save(mode: sel.first),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
        child: Text(tr('theme.cover')),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(palettes.length, (i) {
            final p = palettes[i];
            final sel = i == t.palette;
            return Tooltip(
              message: p.name,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => save(palette: i),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: p.seed,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: sel ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: sel ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              ),
            );
          }),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(tr('theme.paper')),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(
          spacing: 8,
          children: PaperStyle.values
              .map((p) => ChoiceChip(
                    label: Text(paperStyleLabel(p)),
                    selected: t.paper == p,
                    onSelected: (_) => save(paper: p),
                  ))
              .toList(),
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.grid_on),
        title: Text(tr('theme.tablecloth')),
        subtitle: Text(tr('theme.tableclothInfo')),
        value: t.tablecloth,
        onChanged: (v) => save(tablecloth: v),
      ),
    ];
  }

  List<Widget> _familySection(BuildContext context) {
    final groups = appState.data.groups;
    return [
      ...groups.map((g) => ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(g.name),
            subtitle: Text('${trn('family.members', g.members.length)} · ${tr('settings.code', {'code': g.id})}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupScreen(groupId: g.id))),
          )),
      ListTile(
        leading: const Icon(Icons.group_add),
        title: Text(tr('family.create')),
        onTap: () => createGroupDialog(context),
      ),
      ListTile(
        leading: const Icon(Icons.key),
        title: Text(tr('settings.joinInvite')),
        onTap: () => joinGroupDialog(context),
      ),
    ];
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    const auto = '__auto__';
    final codes = [...L10n.available]..sort((a, b) => L10n.names[a]!.compareTo(L10n.names[b]!));
    final sel = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(tr('settings.language'), style: const TextStyle(fontFamily: handFont, fontSize: 24)),
          ),
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(tr('settings.langAuto')),
            trailing: appState.langPref == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, auto),
          ),
          const Divider(height: 1),
          ...codes.map((c) => ListTile(
                title: Text(L10n.names[c]!),
                trailing: appState.langPref == c ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c),
              )),
        ]),
      ),
    );
    if (sel == null) return;
    await appState.setLanguage(sel == auto ? null : sel);
  }

  Widget _header(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Text(t,
            style: TextStyle(fontFamily: handFont, fontSize: 24, color: NotebookColors.of(context).accent)),
      );
}

class _NotifyStatus extends StatefulWidget {
  const _NotifyStatus();

  @override
  State<_NotifyStatus> createState() => _NotifyStatusState();
}

class _NotifyStatusState extends State<_NotifyStatus> with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final e = await appState.notifications.enabled();
      if (mounted) setState(() => _enabled = e);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final e = _enabled;
    if (e == null) return const SizedBox.shrink();
    if (!e) {
      return ListTile(
        leading: Icon(Icons.notifications_off, color: Colors.red.shade700),
        title: Text(tr('settings.blocked'), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(tr('settings.blockedInfo')),
        onTap: () async {
          await appState.notifications.requestPermission();
          await _load();
        },
      );
    }
    return ListTile(
      leading: Icon(Icons.notifications_active, color: Colors.green.shade700),
      title: Text(tr('settings.allowed')),
    );
  }
}
