import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/pdf_export.dart';
import '../services/support_service.dart';
import '../services/sync_service.dart' show cloudErrorMessage;
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/group_qr.dart';
import '../widgets/recipe_browser.dart';
import 'login_screen.dart';
import 'recipe_detail_screen.dart';
import 'new_recipe.dart';

class FamilyTab extends StatelessWidget {
  final void Function(Recipe r) onOpen;
  final void Function(String groupId) onAdd;
  final String? selectedId;
  const FamilyTab({super.key, required this.onOpen, required this.onAdd, this.selectedId});

  static const int _preview = 3;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!appState.isCloud) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(10, 24, 12, 24),
        children: [
          Icon(Icons.groups, size: 72, color: scheme.primary),
          const SizedBox(height: 12),
          Text(tr('family.title'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            appState.auth.cloudAvailable ? tr('family.needCloud') : tr('family.cloudOff'),
            textAlign: TextAlign.center,
          ),
          if (appState.auth.cloudAvailable) ...[
            const SizedBox(height: 16),
            Center(
              child: FilledButton.icon(
                onPressed: () => _push(context, const LoginScreen(upgrade: true)),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(tr('upgrade.button')),
              ),
            ),
          ],
        ],
      );
    }

    final groups = appState.data.groups;
    return RefreshIndicator(
      onRefresh: appState.retrySync,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(4, 6, 10, 32),
        children: [
          if (groups.isEmpty) ...[
            const SizedBox(height: 24),
            Icon(Icons.groups, size: 72, color: scheme.primary),
            const SizedBox(height: 12),
            Text(tr('family.none'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(tr('family.noneHint'), textAlign: TextAlign.center),
            const SizedBox(height: 20),
          ],
          ...groups.map((g) => _groupSection(context, g)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => createGroupDialog(context),
                icon: const Icon(Icons.group_add),
                label: Text(tr('family.create')),
              ),
              OutlinedButton.icon(
                onPressed: () => joinGroupDialog(context),
                icon: const Icon(Icons.key),
                label: Text(tr('family.joinCode')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _groupSection(BuildContext context, FamilyGroup g) {
    final list = appState.groupRecipes(g.id);
    final latest = List.of(list)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final scheme = Theme.of(context).colorScheme;
    final nb = NotebookColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _push(context, GroupBookScreen(groupId: g.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
            child: Row(children: [
              Icon(Icons.groups_outlined, color: nb.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(g.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: handFont, fontSize: 26, color: nb.accent, height: 1.35)),
                  const SizedBox(height: 2),
                  Text(
                      '${trn('family.members', g.members.length)} · ${trn('book.recipes', list.length)} · '
                      '${groupRoleLabel(g.roleOf(appState.session?.key))}',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              if (list.isNotEmpty) _pdfButton(context, g.name, list),
              _settingsButton(context, g.id, iconSize: 20),
            ]),
          ),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(tr('family.noRecipes'), style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        ...latest.take(_preview).map((r) => RecipeCard(
              recipe: r,
              selected: r.id == selectedId,
              onTap: () => onOpen(r),
              onLongPress: () => moveRecipeSheet(context, r),
            )),
        Wrap(spacing: 4, children: [
          if (list.length > _preview)
            TextButton.icon(
              onPressed: () => _push(context, GroupBookScreen(groupId: g.id)),
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(tr('family.seeAll', {'n': list.length})),
            ),
          if (appState.canAddTo(g.id))
            TextButton.icon(
              onPressed: () => onAdd(g.id),
              icon: const Icon(Icons.add),
              label: Text(tr('family.addTo', {'name': g.name})),
            ),
        ]),
      ]),
    );
  }
}

/// Il ricettario completo di un gruppo.
class GroupBookScreen extends StatelessWidget {
  final String groupId;
  const GroupBookScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final g = appState.data.groupById(groupId);
        final list = g == null ? <Recipe>[] : appState.groupRecipes(g.id);
        return TableclothBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              title: Text(g?.name ?? tr('family.defaultName')),
              actions: [
                if (list.isNotEmpty) _pdfButton(context, g!.name, list),
                if (g != null) _settingsButton(context, g.id),
              ],
            ),
            body: NotebookPage(
              child: g == null
                  ? Center(child: Text(tr('family.unavailable')))
                  : RecipeBrowser(
                      recipes: list,
                      onOpen: (r, shown) =>
                          _push(context, RecipeDetailScreen(recipeId: r.id, sequence: [for (final x in shown) x.id])),
                      onLongPress: (r) => moveRecipeSheet(context, r),
                      emptyTitle: tr('family.noRecipes'),
                      emptyHint: appState.canAddTo(g.id) ? tr('family.noRecipesHint') : null,
                    ),
            ),
            floatingActionButton: g != null && appState.canAddTo(g.id)
                ? FloatingActionButton.extended(
                    onPressed: () => newRecipeFlow(context, bookId: g.id),
                    icon: const Icon(Icons.add),
                    label: Text(tr('recipe.new')),
                  )
                : null,
          ),
        );
      },
    );
  }
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

Widget _pdfButton(BuildContext context, String title, List<Recipe> recipes) => IconButton(
      tooltip: tr('pdf.exportGroup'),
      icon: const Icon(Icons.picture_as_pdf_outlined),
      onPressed: () => exportPdf(context, title, recipes),
    );

Widget _settingsButton(BuildContext context, String groupId, {double? iconSize}) => IconButton(
      tooltip: tr('family.settings'),
      icon: Icon(Icons.settings_outlined, size: iconSize),
      onPressed: () => _push(context, GroupScreen(groupId: groupId)),
    );

/// Esegue un'operazione sul cloud; se fallisce mostra l'errore.
Future<void> _cloud(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) showSnack(context, cloudErrorMessage(e));
  }
}

/// Dialogo di conferma: true se l'utente accetta.
Future<bool> _confirm(BuildContext context,
    {required String title, required String body, required String ok, Color? okColor}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
        FilledButton(
          style: okColor == null ? null : FilledButton.styleFrom(backgroundColor: okColor),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return yes == true;
}

/// Chiede un nome; null se annullato, altrimenti il testo senza spazi ai lati.
Future<String?> _askName(BuildContext context,
    {required String title, required String initial, required String ok, String? label, bool words = false}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: words ? TextCapitalization.words : TextCapitalization.none,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(ok)),
      ],
    ),
  );
}

Future<void> exportPdf(BuildContext context, String title, List<Recipe> recipes) async {
  showSnack(context, tr('pdf.creating'));
  try {
    await PdfExport.share(
      title: title,
      recipes: recipes,
      photo: (r, p) => appState.photos.load(p, bookId: appState.bookOf(r)),
      lookup: {for (final r in appState.recipes) r.id: r},
    );
  } catch (e) {
    if (context.mounted) showSnack(context, tr('pdf.error', {'error': e}));
  }
}

Future<void> moveRecipeSheet(BuildContext context, Recipe r) async {
  HapticFeedback.mediumImpact();
  if (!appState.isCloud) {
    showSnack(context, tr('move.needCloud'));
    return;
  }
  const personalKey = '__personal__';
  final canEdit = appState.canEdit(r);
  final groups = appState.data.groups.where((g) => g.id != r.bookId && appState.canAddTo(g.id)).toList();
  final personal = appState.isPersonal(r);
  final name = r.displayTitle;
  final dest = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(personal ? tr('move.addTitle', {'name': name}) : tr('move.moveTitle', {'name': name}),
                style: const TextStyle(fontFamily: handFont, fontSize: 24)),
          ),
          if (canEdit)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                personal ? tr('move.addInfo') : tr('move.moveInfo', {'name': appState.bookLabel(r)}),
                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
          if (canEdit && groups.isEmpty && personal)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(tr('move.noGroups')),
              subtitle: Text(tr('move.noGroupsHint')),
              onTap: () => Navigator.pop(ctx),
            ),
          if (canEdit)
            ...groups.map((g) => ListTile(
                  leading: const Icon(Icons.groups_outlined),
                  title: Text(g.name),
                  subtitle: Text(trn('family.members', g.members.length)),
                  onTap: () => Navigator.pop(ctx, g.id),
                )),
          if (canEdit && !personal)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(tr('book.mine')),
              subtitle: Text(tr('move.onlyYou')),
              onTap: () => Navigator.pop(ctx, personalKey),
            ),
          if (!personal)
            ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: Text(tr('recipe.copyMine')),
              subtitle: Text(tr('recipe.copyMineInfo')),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
  if (dest == null || !context.mounted) return;
  if (dest == 'copy') {
    await copyToMine(context, r);
    return;
  }
  final target = dest == personalKey ? null : dest;
  final label = target == null ? tr('book.mine') : (appState.data.groupById(target)?.name ?? tr('family.defaultName'));
  await appState.moveRecipe(r.id, target);
  if (context.mounted) showSnack(context, tr('move.done', {'name': name, 'where': label}));
}

Future<void> copyToMine(BuildContext context, Recipe r) async {
  showSnack(context, tr('recipe.copying'));
  final c = await appState.duplicateRecipe(r, null);
  if (context.mounted && c != null) showSnack(context, tr('recipe.copied', {'name': r.displayTitle}));
}

Future<void> createGroupDialog(BuildContext context) async {
  final name = await _askName(
    context,
    title: tr('family.newTitle'),
    initial: tr('family.defaultName'),
    ok: tr('common.create'),
    label: tr('family.nameHint'),
    words: true,
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  await _cloud(context, () async {
    final g = await appState.createGroup(name);
    if (context.mounted) _push(context, GroupScreen(groupId: g.id));
  });
}

Future<void> joinGroupDialog(BuildContext context) async {
  final c = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('family.inviteCode')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr('family.enterCode')),
        const SizedBox(height: 12),
        TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: tr('family.codeHint')),
        ),
        const SizedBox(height: 8),
        Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
          for (final (icon, label, read) in [
            (Icons.qr_code_scanner, 'family.scanQr', scanGroupQr),
            (Icons.image_outlined, 'family.qrFromImage', groupQrFromImage),
          ])
            TextButton.icon(
              icon: Icon(icon),
              label: Text(tr(label)),
              onPressed: () async {
                final code = await read(ctx);
                if (code != null && ctx.mounted) Navigator.pop(ctx, code);
              },
            ),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('family.join'))),
      ],
    ),
  );
  if (code == null || code.isEmpty || !context.mounted) return;
  await _cloud(context, () async {
    final g = await appState.joinGroup(code);
    if (context.mounted) showSnack(context, tr('family.joined', {'name': g.name}));
  });
}

/// Impostazioni di un gruppo: codice invito, QR, membri e ruoli.
class GroupScreen extends StatelessWidget {
  final String groupId;
  const GroupScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final g = appState.data.groupById(groupId);
        if (g == null) {
          return TableclothBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(),
              body: NotebookPage(child: Center(child: Text(tr('family.unavailable')))),
            ),
          );
        }
        final me = appState.session?.key;
        final isOwner = g.ownerUid == me;
        final manage = appState.canManage(g);
        final scheme = Theme.of(context).colorScheme;
        return TableclothBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: Text(g.name)),
            body: NotebookPage(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 32),
                children: [
                  HandHeader(tr('family.inviteCode'), icon: Icons.key),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                          child: SelectableText(g.id,
                              style: const TextStyle(fontSize: 24, letterSpacing: 3, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          tooltip: tr('common.copy'),
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: g.id));
                            showSnack(context, tr('family.codeCopied'));
                          },
                        ),
                      ]),
                    ),
                  ),
                  Text(tr('family.inviteHowTo'), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  GroupQrCard(code: g.id, groupName: g.name),
                  HandHeader(tr('family.membersTitle', {'n': g.members.length}), icon: Icons.people_outline),
                  ...g.members.entries.map((m) {
                    final role = g.roleOf(m.key);
                    final owner = m.key == g.ownerUid;
                    final editable = manage && !owner && m.key != me;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          owner
                              ? Icons.star
                              : switch (role) {
                                  GroupRole.admin => Icons.admin_panel_settings_outlined,
                                  GroupRole.viewer => Icons.visibility_outlined,
                                  _ => Icons.person_outline,
                                },
                          color: owner ? Colors.amber.shade700 : null),
                      title: Text(m.value + (m.key == me ? ' ${tr('family.you')}' : '')),
                      subtitle: Text(owner ? '${tr('family.owner')} · ${groupRoleLabel(role)}' : groupRoleLabel(role)),
                      onTap: editable ? () => _changeRole(context, g, m.key, m.value) : null,
                      trailing: editable
                          ? IconButton(
                              tooltip: tr('common.remove'),
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () => role == GroupRole.admin && !appState.isAdmin
                                  ? _adminLocked(context, g, m.value)
                                  : _removeMember(context, g, m.key, m.value),
                            )
                          : null,
                    );
                  }),
                  if (manage)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(tr('role.hint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 20),
                  if (manage)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(tr('family.rename')),
                      onTap: () => _rename(context, g),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(isOwner ? Icons.delete_forever_outlined : Icons.exit_to_app, color: Colors.red.shade700),
                    title: Text(isOwner ? tr('family.delete') : tr('family.leave')),
                    subtitle: Text(isOwner ? tr('family.deleteInfo') : tr('family.leaveInfo')),
                    onTap: () => _leave(context, g, isOwner),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _changeRole(BuildContext context, FamilyGroup g, String uid, String name) async {
    final current = g.roleOf(uid);
    final picked = await showDialog<GroupRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('role.changeFor', {'name': name})),
        children: GroupRole.values
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r),
                  child: Row(children: [
                    Icon(r == current ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(groupRoleLabel(r)),
                        Text(tr('role.${r.name}Info'),
                            style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                      ]),
                    ),
                  ]),
                ))
            .toList(),
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;
    if (current == GroupRole.admin && !appState.isAdmin) {
      await _adminLocked(context, g, name);
      return;
    }
    await _cloud(context, () => appState.setRole(g, uid, picked));
  }

  Future<void> _adminLocked(BuildContext context, FamilyGroup g, String name) async {
    final contact =
        await _confirm(context, title: tr('role.admin'), body: tr('role.adminLocked'), ok: tr('role.contactSupport'));
    if (!contact) return;
    final ok = await SupportService.openEmail(
      subject: 'FamilyRecipes - ${tr('role.adminLocked')}',
      body: '${tr('family.inviteCode')}: ${g.id}\n${g.name}\n$name\n\n'
          '${appState.session?.email ?? appState.session?.displayName ?? ''}\n',
    );
    if (!ok && context.mounted) showSnack(context, SupportService.email);
  }

  Future<void> _rename(BuildContext context, FamilyGroup g) async {
    final name = await _askName(context, title: tr('family.nameTitle'), initial: g.name, ok: tr('common.save'));
    if (name == null || name.isEmpty) return;
    await _cloud(context, () => appState.renameGroup(g.id, name));
  }

  Future<void> _removeMember(BuildContext context, FamilyGroup g, String uid, String email) async {
    final ok = await _confirm(context,
        title: tr('family.removeTitle'),
        body: tr('family.removeBody', {'email': email, 'name': g.name}),
        ok: tr('common.remove'));
    if (!ok) return;
    await _cloud(context, () => appState.removeMember(g.id, uid));
  }

  Future<void> _leave(BuildContext context, FamilyGroup g, bool isOwner) async {
    final ok = await _confirm(context,
        title: isOwner ? tr('family.deleteTitle') : tr('family.leaveTitle'),
        body: isOwner ? tr('family.deleteBody', {'name': g.name}) : tr('family.leaveBody', {'name': g.name}),
        ok: isOwner ? tr('common.delete') : tr('family.leaveShort'),
        okColor: Colors.red.shade700);
    if (!ok) return;
    await _cloud(context, () async {
      await (isOwner ? appState.deleteGroup(g.id) : appState.leaveGroup(g.id));
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    });
  }
}
