import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/sync_service.dart' show cloudErrorMessage;
import '../theme.dart';
import '../widgets/common.dart';
import 'recipe_detail_screen.dart';

/// Amministrazione dell'app (solo per l'account amministratore):
/// tutte le ricette con il loro autore, e tutti i gruppi con i ruoli dei membri.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  static Widget error(Object e) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('${tr('admin.denied')}\n\n${cloudErrorMessage(e)}', textAlign: TextAlign.center),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    return DefaultTabController(
      length: 2,
      child: TableclothBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(tr('admin.title')),
            bottom: TabBar(
              labelColor: nb.onCover,
              unselectedLabelColor: nb.onCover.withValues(alpha: 0.7),
              indicatorColor: nb.onCover,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w600),
              tabs: [
                Tab(icon: const Icon(Icons.menu_book_outlined), text: tr('admin.recipes')),
                Tab(icon: const Icon(Icons.groups_outlined), text: tr('admin.groups')),
              ],
            ),
          ),
          body: const NotebookPage(
            child: TabBarView(children: [AdminRecipesTab(), AdminGroupsTab()]),
          ),
        ),
      ),
    );
  }
}

class _AdminUser {
  final String uid;
  String name = '';
  String email = '';
  _AdminUser(this.uid);

  String get label => name.isNotEmpty ? name : (email.isNotEmpty ? email : uid);
  String get detail => email.isNotEmpty && email != label ? email : uid;
}

class AdminRecipesTab extends StatefulWidget {
  const AdminRecipesTab({super.key});

  @override
  State<AdminRecipesTab> createState() => _AdminRecipesTabState();
}

class _AdminRecipesTabState extends State<AdminRecipesTab> {
  final _search = TextEditingController();
  late final Stream<List<Recipe>> _recipes = appState.sync.watchAllRecipes();
  late final Stream<List<Map<String, dynamic>>> _books = appState.sync.watchAllBooks();
  late final Stream<List<Map<String, dynamic>>> _users = appState.sync.watchAllUsers();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, _AdminUser> _people(List<Map<String, dynamic>> users, List<Map<String, dynamic>> books) {
    final out = <String, _AdminUser>{};
    for (final f in books) {
      final emails = Map<String, dynamic>.from((f['memberEmails'] as Map?) ?? {});
      emails.forEach((uid, e) => out.putIfAbsent(uid, () => _AdminUser(uid)).email = e.toString());
    }
    for (final u in users) {
      final uid = u['uid'] as String;
      final p = out.putIfAbsent(uid, () => _AdminUser(uid));
      final name = (u['name'] as String?)?.trim() ?? '';
      final email = (u['email'] as String?)?.trim() ?? '';
      if (name.isNotEmpty) p.name = name;
      if (email.isNotEmpty) p.email = email;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _books,
      builder: (context, fs) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: _users,
        builder: (context, us) => StreamBuilder<List<Recipe>>(
          stream: _recipes,
          builder: (context, rs) {
            final err = fs.error ?? us.error ?? rs.error;
            if (err != null) return AdminScreen.error(err);
            if (!fs.hasData || !us.hasData || !rs.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final books = {for (final f in fs.data!) f['id'] as String: f};
            return _content(context, rs.data!, books, _people(us.data!, fs.data!));
          },
        ),
      ),
    );
  }

  bool _personal(Map<String, dynamic>? f) => f?['personal'] == true;

  String _owner(Recipe r, Map<String, Map<String, dynamic>> books) {
    if (r.createdBy.isNotEmpty) return r.createdBy;
    final f = books[r.bookId];
    return _personal(f) ? (f?['ownerUid'] as String? ?? r.bookId!) : '';
  }

  Widget _content(BuildContext context, List<Recipe> all, Map<String, Map<String, dynamic>> books,
      Map<String, _AdminUser> people) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    String who(String uid) => uid.isEmpty ? tr('admin.unknown') : (people[uid]?.label ?? uid);
    String where(Recipe r) {
      final f = books[r.bookId];
      if (_personal(f)) return tr('admin.personalOf', {'name': who(f?['ownerUid'] as String? ?? r.bookId!)});
      return tr('admin.groupNamed', {'name': (f?['name'] as String?) ?? r.bookId});
    }

    final q = _search.text.trim().toLowerCase();
    final list = all.where((r) {
      if (q.isEmpty) return true;
      final o = _owner(r, books);
      return '${r.title} ${categoryLabel(r.category)} ${who(o)} ${people[o]?.email ?? ''} ${where(r)}'
          .toLowerCase()
          .contains(q);
    }).toList()
      ..sort((a, b) {
        final c = who(_owner(a, books)).toLowerCase().compareTo(who(_owner(b, books)).toLowerCase());
        return c != 0 ? c : a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 12, 10, 24),
      children: [
        Text(tr('admin.allRecipes', {'n': all.length}),
            style: TextStyle(fontFamily: handFont, fontSize: 22, color: nb.accent)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(tr('admin.recipesInfo'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tr('admin.searchRecipes'),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(child: Text(tr('admin.noRecipes'))),
          ),
        ...list.map((r) {
          final owner = _owner(r, books);
          final local = appState.recipeById(r.id);
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              leading: Icon(categoryIcon(r.category), color: scheme.primary),
              title: Text(r.displayTitle),
              subtitle: Text(
                '${tr('admin.author', {'name': who(owner)})}\n${where(r)}\n${categoryLabel(r.category)}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
              onTap: local == null
                  ? null
                  : () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: local.id))),
              trailing: TextButton(
                onPressed: () => _assign(context, r, owner, books, people),
                child: Text(tr('admin.assign')),
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _assign(BuildContext context, Recipe r, String owner, Map<String, Map<String, dynamic>> books,
      Map<String, _AdminUser> people) async {
    final f = books[r.bookId];
    final personal = _personal(f);
    final groupMembers = ((f?['members'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final candidates = people.values
        .where((p) => p.uid != owner && (personal || groupMembers.contains(p.uid)))
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final picked = await showDialog<_AdminUser>(
      context: context,
      builder: (ctx) => _UserPicker(
        users: candidates,
        hint: personal ? null : tr('admin.onlyMembers', {'name': f?['name'] ?? r.bookId}),
      ),
    );
    if (picked == null || !context.mounted) return;
    final title = r.displayTitle;
    final oldName = owner.isEmpty ? tr('admin.unknown') : (people[owner]?.label ?? owner);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('admin.assignTitle', {'recipe': title, 'name': picked.label})),
        content: Text(personal
            ? tr('admin.assignPersonal', {'recipe': title, 'name': picked.label, 'old': oldName})
            : tr('admin.assignGroup', {'recipe': title, 'name': picked.label, 'group': f?['name'] ?? r.bookId})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('admin.assign'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await appState.sync.reassignRecipe(r, picked.uid, picked.label, personal: personal, admin: appState.session!);
      if (context.mounted) showSnack(context, tr('admin.assigned', {'recipe': title, 'name': picked.label}));
    } catch (err) {
      if (context.mounted) showSnack(context, cloudErrorMessage(err));
    }
  }
}

class _UserPicker extends StatefulWidget {
  final List<_AdminUser> users;
  final String? hint;
  const _UserPicker({required this.users, this.hint});

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final list = widget.users.where((u) => q.isEmpty || '${u.name} ${u.email} ${u.uid}'.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text(tr('admin.newAuthor')),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(children: [
          if (widget.hint != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(widget.hint!, style: const TextStyle(fontSize: 12)),
            ),
          TextField(
            autofocus: true,
            onChanged: (t) => setState(() => _q = t.trim()),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('admin.nameOrEmail'), isDense: true),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(tr('admin.noUsers')))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (ctx, i) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.person_outline),
                      title: Text(list[i].label),
                      subtitle: Text(list[i].detail),
                      onTap: () => Navigator.pop(ctx, list[i]),
                    ),
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('common.cancel')))],
    );
  }
}

class AdminGroupsTab extends StatelessWidget {
  const AdminGroupsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: appState.sync.watchAllBooks(),
      builder: (context, snap) {
        if (snap.hasError) return AdminScreen.error(snap.error!);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final groups = snap.data!
            .where((f) => f['personal'] != true)
            .map((f) => FamilyGroup.fromDoc(f['id'] as String, f))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 12, 10, 24),
          children: [
            Text(tr('admin.groupsCount', {'n': groups.length}),
                style: TextStyle(fontFamily: handFont, fontSize: 22, color: nb.accent)),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(tr('admin.groupsInfo'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            ...groups.map((g) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ExpansionTile(
                    leading: Icon(Icons.groups_outlined, color: scheme.primary),
                    title: Text(g.name),
                    subtitle: Text(tr('admin.groupLine', {'n': g.members.length, 'code': g.id}),
                        style: const TextStyle(fontSize: 12)),
                    children: g.members.entries.map((m) {
                      final role = g.roleOf(m.key);
                      final owner = m.key == g.ownerUid;
                      return ListTile(
                        dense: true,
                        leading: Icon(owner ? Icons.star : Icons.person_outline,
                            color: owner ? Colors.amber.shade700 : null),
                        title: Text(m.value),
                        subtitle: Text(owner ? '${tr('family.owner')} · ${groupRoleLabel(role)}' : groupRoleLabel(role)),
                        onTap: owner ? null : () => _change(context, g, m.key, m.value, role),
                      );
                    }).toList(),
                  ),
                )),
          ],
        );
      },
    );
  }

  Future<void> _change(BuildContext context, FamilyGroup g, String uid, String name, GroupRole current) async {
    final picked = await showDialog<GroupRole>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('admin.roleOf', {'name': name, 'group': g.name})),
        children: GroupRole.values
            .map((r) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, r),
                  child: Row(children: [
                    Icon(r == current ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                    const SizedBox(width: 10),
                    Text(groupRoleLabel(r)),
                  ]),
                ))
            .toList(),
      ),
    );
    if (picked == null || picked == current) return;
    try {
      await appState.sync.setRole(g.id, uid, picked);
      if (context.mounted) showSnack(context, '$name: ${groupRoleLabel(picked)}');
    } catch (err) {
      if (context.mounted) showSnack(context, cloudErrorMessage(err));
    }
  }
}
