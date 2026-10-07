import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  final bool upgrade;
  const LoginScreen({super.key, this.upgrade = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  late AccountMode _mode = widget.upgrade || appState.auth.cloudAvailable
      ? AccountMode.cloud
      : AccountMode.local;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _pass2.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Session> Function() action) async {
    setState(() => _busy = true);
    try {
      final s = await action();
      if (widget.upgrade) {
        await _finishUpgrade(s);
      } else {
        await appState.login(s);
      }
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishUpgrade(Session s) async {
    final count = appState.myRecipes.length;
    var bring = false;
    if (count > 0 && mounted) {
      bring = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text(tr('upgrade.bringTitle')),
              content: Text(trn('upgrade.bringBody', count)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.no'))),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('upgrade.bringYes'))),
              ],
            ),
          ) ??
          false;
    }
    final copied = await appState.switchToCloud(s, bringRecipes: bring);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).popUntil((r) => r.isFirst);
    messenger.showSnackBar(SnackBar(
        content: Text(copied > 0 ? trn('upgrade.doneWith', copied) : tr('upgrade.done'))));
  }

  Future<void> _forgot() async {
    final email = _user.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showSnack(context, tr('login.forgotNeedEmail'));
      return;
    }
    try {
      await appState.auth.resetPassword(email);
      if (mounted) showSnack(context, tr('login.forgotSent', {'email': email}));
    } catch (e) {
      if (mounted) showSnack(context, e.toString());
    }
  }

  void _submit() {
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      showSnack(context, tr('login.fillAll'));
      return;
    }
    if (_register && p != _pass2.text) {
      showSnack(context, tr('login.passMismatch'));
      return;
    }
    final auth = appState.auth;
    if (_mode == AccountMode.local) {
      _run(() => _register ? auth.registerLocal(u, p) : auth.loginLocal(u, p));
    } else {
      _run(() => _register ? auth.registerCloud(u, p) : auth.loginCloud(u, p));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = appState.auth.cloudAvailable;
    final showModes = cloud && !widget.upgrade;
    final scheme = Theme.of(context).colorScheme;
    final isLocal = _mode == AccountMode.local;
    final cover = NotebookColors.of(context).cover;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(cover, Colors.white, 0.12)!,
              Color.lerp(cover, Colors.black, 0.35)!,
            ],
          ),
        ),
        child: SafeArea(
        child: Stack(children: [
        if (widget.upgrade)
          Positioned(
            top: 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: tr('common.close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 18, offset: Offset(0, 8)),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Image.asset('assets/icon.png', width: 110, height: 110),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('FamilyRecipes',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: handFont, fontSize: 44, color: Color(0xFFFFF7E4))),
                  const SizedBox(height: 4),
                  Text(widget.upgrade ? tr('upgrade.subtitle') : tr('login.tagline'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: handFont, fontSize: 19, color: Color(0xCCFFF7E4))),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 10,
                    color: scheme.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                  if (showModes) ...[
                    SegmentedButton<AccountMode>(
                      segments: [
                        ButtonSegment(
                            value: AccountMode.cloud,
                            icon: const Icon(Icons.groups),
                            label: Text(tr('login.modeCloud'))),
                        ButtonSegment(
                            value: AccountMode.local,
                            icon: const Icon(Icons.phone_android),
                            label: Text(tr('login.modeLocal'))),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) => setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isLocal ? tr('login.localInfo') : tr('login.cloudInfo'),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _user,
                    keyboardType:
                        isLocal ? TextInputType.text : TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      filled: true,
                      labelText: isLocal ? tr('login.username') : tr('login.email'),
                      prefixIcon: Icon(isLocal ? Icons.person : Icons.email),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    obscureText: _hide,
                    textInputAction:
                        _register ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_register) _submit();
                    },
                    decoration: InputDecoration(
                      filled: true,
                      labelText: tr('login.password'),
                      prefixIcon: const Icon(Icons.lock),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                  ),
                  if (_register) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass2,
                      obscureText: _hide,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        filled: true,
                        labelText: tr('login.password2'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? tr('login.create') : tr('login.signIn')),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? tr('login.haveAccount') : tr('login.noAccount')),
                  ),
                  if (!isLocal && !_register)
                    TextButton(
                      onPressed: _busy ? null : _forgot,
                      child: Text(tr('login.forgot')),
                    ),
                  if (cloud && !isLocal) ...[
                    Row(children: [
                      const Expanded(child: Divider()),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(tr('login.or'))),
                      const Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(appState.auth.loginGoogle),
                      icon: const Icon(Icons.g_mobiledata, size: 32),
                      label: Text(tr('login.google')),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10)),
                    ),
                    const SizedBox(height: 6),
                    Text(tr('login.googleInfo'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                  if (!cloud) ...[
                    const SizedBox(height: 16),
                    Text(
                      tr('login.noCloud'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                  ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ]),
        ),
      ),
    );
  }
}
