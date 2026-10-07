import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/photo_tools.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'photo_crop_screen.dart';

class _IngRow {
  final TextEditingController name;
  final TextEditingController amount;
  final Key key = UniqueKey();
  _IngRow(Ingredient i)
      : name = TextEditingController(text: i.name),
        amount = TextEditingController(text: i.amount);

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _StepRow {
  final String id;
  final TextEditingController text;
  final List<String> photos;
  _StepRow(RecipeStep s)
      : id = s.id,
        text = TextEditingController(text: s.text),
        photos = List.of(s.photos);
}

class RecipeEditScreen extends StatefulWidget {
  /// Copia di lavoro: viene salvata solo con "Salva".
  final Recipe recipe;
  const RecipeEditScreen({super.key, required this.recipe});

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  late final Recipe r = widget.recipe;
  late final bool _isNew = appState.recipeById(r.id) == null;
  late final String _initial;

  late final _title = TextEditingController(text: r.title);
  late final _intro = TextEditingController(text: r.intro);
  late final _tips = TextEditingController(text: r.tips);
  late final _prep = TextEditingController(text: r.prepMinutes > 0 ? '${r.prepMinutes}' : '');
  late final _cook = TextEditingController(text: r.cookMinutes > 0 ? '${r.cookMinutes}' : '');
  late final List<_IngRow> _ings = [for (final i in r.ingredients) _IngRow(i)];
  late final List<_StepRow> _steps = [for (final s in r.steps) _StepRow(s)];

  /// Foto aggiunte in questa sessione: si cancellano se non vengono salvate.
  final Set<String> _added = {};
  bool _saving = false;
  bool _busyPhoto = false;

  @override
  void initState() {
    super.initState();
    if (_ings.isEmpty) _ings.add(_IngRow(Ingredient()));
    if (_steps.isEmpty) _steps.add(_StepRow(RecipeStep()));
    _initial = _normalized();
  }

  @override
  void dispose() {
    _title.dispose();
    _intro.dispose();
    _tips.dispose();
    _prep.dispose();
    _cook.dispose();
    for (final i in _ings) {
      i.dispose();
    }
    for (final s in _steps) {
      s.text.dispose();
    }
    super.dispose();
  }

  void _collect() {
    r.title = _title.text.trim();
    r.intro = _intro.text.trim();
    r.tips = _tips.text.trim();
    r.prepMinutes = int.tryParse(_prep.text.trim()) ?? 0;
    r.cookMinutes = int.tryParse(_cook.text.trim()) ?? 0;
    r.ingredients = [
      for (final i in _ings) Ingredient(name: i.name.text.trim(), amount: i.amount.text.trim()),
    ];
    r.steps = [
      for (final s in _steps) RecipeStep(id: s.id, text: s.text.text.trim(), photos: List.of(s.photos)),
    ];
    if (r.category != RecipeCategory.menu) r.courses = [];
  }

  String _normalized() {
    _collect();
    final c = r.copy()
      ..ingredients.removeWhere((i) => i.isEmpty)
      ..steps.removeWhere((s) => s.isEmpty);
    return jsonEncode(c.toJson());
  }

  bool get _dirty => _normalized() != _initial || _added.isNotEmpty;

  Future<void> _discardPhotos() async {
    for (final p in _added) {
      await appState.photos.delete(p);
    }
    _added.clear();
  }

  Future<void> _save() async {
    if (_saving) return;
    _collect();
    if (r.title.isEmpty) {
      showSnack(context, tr('edit.needTitle'));
      return;
    }
    setState(() => _saving = true);
    final used = r.photoIds;
    for (final p in _added.where((p) => !used.contains(p)).toList()) {
      await appState.photos.delete(p);
    }
    _added.clear();
    await appState.saveRecipe(r);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) {
      await _discardPhotos();
      return true;
    }
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('edit.unsavedTitle')),
        content: Text(tr('edit.unsavedBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: Text(tr('edit.discard'))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('common.save'))),
        ],
      ),
    );
    if (res == 'save') {
      await _save();
      return false;
    }
    if (res == 'discard') {
      await _discardPhotos();
      return true;
    }
    return false;
  }

  // ---- Foto ----

  Future<ImageSource?> _askSource({bool canRemove = false, VoidCallback? onRemove}) =>
      showModalBottomSheet<ImageSource>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: Text(tr('photo.camera')),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(tr('photo.gallery')),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            if (canRemove)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(tr('photo.remove')),
                onTap: () {
                  Navigator.pop(ctx);
                  onRemove?.call();
                },
              ),
          ]),
        ),
      );

  Future<String> _store(Uint8List bytes) async {
    final id = await appState.addPhoto(bytes);
    _added.add(id);
    return id;
  }

  Future<void> _pickCover() async {
    final src = await _askSource(
      canRemove: r.coverPhoto != null,
      onRemove: () => setState(() => r.coverPhoto = null),
    );
    if (src == null) return;
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 2400, maxHeight: 2400, imageQuality: 92);
      if (x == null || !mounted) return;
      final cropped = await cropPhoto(context, await x.readAsBytes(),
          aspect: 4 / 3, maxSide: photoMaxSide, quality: photoQuality);
      if (cropped == null || !mounted) return;
      final id = await _store(cropped);
      if (mounted) setState(() => r.coverPhoto = id);
    } catch (e) {
      if (mounted) showSnack(context, tr('photo.error', {'error': e}));
    }
  }

  Future<void> _addStepPhotos(_StepRow s) async {
    final src = await _askSource();
    if (src == null) return;
    setState(() => _busyPhoto = true);
    try {
      final picker = ImagePicker();
      final files = src == ImageSource.camera
          ? [if (await picker.pickImage(source: src, maxWidth: 2000, maxHeight: 2000, imageQuality: 90) case final x?) x]
          : await picker.pickMultiImage(maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
      for (final f in files) {
        final bytes = await compressPhoto(await f.readAsBytes());
        final id = await _store(bytes);
        if (mounted) setState(() => s.photos.add(id));
      }
    } catch (e) {
      if (mounted) showSnack(context, tr('photo.error', {'error': e}));
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
    }
  }

  // ---- Menù ----

  Future<void> _addCourse() async {
    _collect();
    final options = appState.menuCandidates(r).where((c) => !r.courses.contains(c.id)).toList();
    if (options.isEmpty) {
      showSnack(context, tr('edit.noCourses'));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(tr('edit.pickCourse'), style: const TextStyle(fontFamily: handFont, fontSize: 24)),
            ),
            for (final c in RecipeCategory.values)
              for (final o in options.where((o) => o.category == c))
                ListTile(
                  leading: Icon(categoryIcon(o.category)),
                  title: Text(o.displayTitle),
                  subtitle: Text(categoryLabel(o.category)),
                  onTap: () => Navigator.pop(ctx, o.id),
                ),
          ]),
        ),
      ),
    );
    if (picked != null) setState(() => r.courses.add(picked));
  }

  // ---- Interfaccia ----

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && mounted) nav.pop();
      },
      child: TableclothBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: Text(_isNew ? tr('edit.newTitle') : tr('edit.editTitle')),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: nb.onCover),
                onPressed: _saving || _busyPhoto ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(tr('common.save')),
              ),
            ],
          ),
          body: NotebookPage(
            lines: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 60),
              children: [
                if (_isNew && appState.isCloud) _bookPicker(),
                _categoryPicker(),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(fontFamily: handFont, fontSize: 26, color: nb.ink),
                  decoration: InputDecoration(labelText: tr('edit.title'), hintText: tr('edit.titleHint')),
                ),
                const SizedBox(height: 12),
                _coverBox(),
                const SizedBox(height: 12),
                TextField(
                  controller: _intro,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: tr('edit.intro'),
                    hintText: tr('edit.introHint'),
                    alignLabelWithHint: true,
                  ),
                ),
                HandHeader(tr('edit.info'), icon: Icons.info_outline),
                _infoFields(),
                if (r.category == RecipeCategory.menu) ..._coursesSection(),
                HandHeader(tr('recipe.ingredients'), icon: Icons.shopping_basket_outlined),
                _ingredients(),
                HandHeader(tr('recipe.steps'), icon: Icons.format_list_numbered),
                for (var i = 0; i < _steps.length; i++) _stepCard(i),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _steps.add(_StepRow(RecipeStep()))),
                    icon: const Icon(Icons.add),
                    label: Text(tr('edit.addStep')),
                  ),
                ),
                HandHeader(tr('recipe.tips'), icon: Icons.lightbulb_outline),
                TextField(
                  controller: _tips,
                  minLines: 2,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(hintText: tr('edit.tipsHint')),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saving || _busyPhoto ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Text(tr('edit.saveRecipe')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookPicker() {
    final groups = appState.data.groups.where((g) => appState.canAddTo(g.id)).toList();
    if (groups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: r.bookId,
        decoration: InputDecoration(labelText: tr('edit.whereSave'), prefixIcon: const Icon(Icons.menu_book_outlined)),
        items: [
          DropdownMenuItem(value: null, child: Text(tr('book.mine'))),
          for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name)),
        ],
        onChanged: (v) => setState(() {
          r.bookId = v;
          r.courses.clear();
        }),
      ),
    );
  }

  Widget _categoryPicker() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('edit.category'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in RecipeCategory.values)
          ChoiceChip(
            avatar: Icon(categoryIcon(c), size: 18),
            label: Text(categoryLabel(c)),
            selected: r.category == c,
            onSelected: (_) => setState(() => r.category = c),
          ),
      ]),
    ]);
  }

  Widget _coverBox() {
    final scheme = Theme.of(context).colorScheme;
    final nb = NotebookColors.of(context);
    final cover = r.coverPhoto;
    return InkWell(
      onTap: _pickCover,
      borderRadius: BorderRadius.circular(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: cover != null
              ? Stack(fit: StackFit.expand, children: [
                  RecipePhoto(photoId: cover, recipe: r),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: const Icon(Icons.edit, color: Colors.white, size: 20),
                    ),
                  ),
                ])
              : Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    border: Border.all(color: nb.line, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_a_photo_outlined, size: 44, color: scheme.primary),
                    const SizedBox(height: 6),
                    Text(tr('edit.coverPhoto'), style: TextStyle(fontFamily: handFont, fontSize: 22, color: nb.ink)),
                    Text(tr('edit.coverPhotoHint'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
                ),
        ),
      ),
    );
  }

  Widget _infoFields() {
    final digits = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)];
    final label = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('recipe.difficulty'), style: label),
      const SizedBox(height: 4),
      SegmentedButton<Difficulty>(
        showSelectedIcon: false,
        segments: [
          for (final d in Difficulty.values)
            ButtonSegment(
                value: d,
                label: FittedBox(fit: BoxFit.scaleDown, child: Text(difficultyLabel(d), maxLines: 1))),
        ],
        selected: {r.difficulty},
        onSelectionChanged: (s) => setState(() => r.difficulty = s.first),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _prep,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
              labelText: tr('recipe.prep'),
              suffixText: tr('edit.minutes'),
              prefixIcon: const Icon(Icons.timer_outlined),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _cook,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
              labelText: tr('recipe.cook'),
              suffixText: tr('edit.minutes'),
              prefixIcon: const Icon(Icons.local_fire_department_outlined),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        const Icon(Icons.people_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(tr('recipe.servings'))),
        IconButton(
          onPressed: r.servings > 0 ? () => setState(() => r.servings--) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 44,
          child: Text(r.servings > 0 ? '${r.servings}' : '—',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          onPressed: r.servings < 99 ? () => setState(() => r.servings++) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ]),
      const SizedBox(height: 8),
      Text(tr('recipe.cost'), style: label),
      const SizedBox(height: 4),
      SegmentedButton<Cost>(
        showSelectedIcon: false,
        segments: [
          for (final c in Cost.values)
            ButtonSegment(value: c, label: FittedBox(fit: BoxFit.scaleDown, child: Text(costLabel(c), maxLines: 1))),
        ],
        selected: {r.cost},
        onSelectionChanged: (s) => setState(() => r.cost = s.first),
      ),
    ]);
  }

  List<Widget> _coursesSection() {
    final courses = r.courses.map(appState.recipeById).whereType<Recipe>().toList();
    return [
      HandHeader(tr('recipe.courses'), icon: Icons.restaurant_menu),
      Text(tr('edit.coursesHint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      for (final c in courses)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            leading: RecipeThumb(recipe: c, size: 40),
            title: Text(c.displayTitle),
            subtitle: Text(categoryLabel(c.category)),
            trailing: IconButton(
              tooltip: tr('common.remove'),
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => r.courses.remove(c.id)),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: _addCourse, icon: const Icon(Icons.add), label: Text(tr('edit.addCourse'))),
      ),
    ];
  }

  Widget _ingredients() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr('edit.ingredientsHint'),
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (a, b) => setState(() {
          if (b > a) b--;
          _ings.insert(b, _ings.removeAt(a));
        }),
        children: [
          for (var i = 0; i < _ings.length; i++)
            Padding(
              key: _ings[i].key,
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                ReorderableDragStartListener(
                  index: i,
                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.drag_indicator)),
                ),
                Expanded(
                  flex: 5,
                  child: TextField(
                    controller: _ings[i].name,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(isDense: true, hintText: tr('edit.ingredient')),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ings[i].amount,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      if (i == _ings.length - 1) setState(() => _ings.add(_IngRow(Ingredient())));
                    },
                    decoration: InputDecoration(isDense: true, hintText: tr('edit.amount')),
                  ),
                ),
                IconButton(
                  tooltip: tr('common.remove'),
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _ings.removeAt(i).dispose()),
                ),
              ]),
            ),
        ],
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _ings.add(_IngRow(Ingredient()))),
          icon: const Icon(Icons.add),
          label: Text(tr('edit.addIngredient')),
        ),
      ),
    ]);
  }

  Widget _stepCard(int i) {
    final s = _steps[i];
    final nb = NotebookColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey(s.id),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: nb.accent, shape: BoxShape.circle),
              child: Text('${i + 1}', style: TextStyle(fontFamily: handFont, fontSize: 20, color: scheme.onPrimary)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('edit.stepN', {'n': i + 1}),
                  style: TextStyle(fontFamily: handFont, fontSize: 21, color: nb.ink)),
            ),
            IconButton(
              tooltip: tr('edit.moveUp'),
              icon: const Icon(Icons.arrow_upward),
              onPressed: i == 0 ? null : () => setState(() => _steps.insert(i - 1, _steps.removeAt(i))),
            ),
            IconButton(
              tooltip: tr('edit.moveDown'),
              icon: const Icon(Icons.arrow_downward),
              onPressed:
                  i == _steps.length - 1 ? null : () => setState(() => _steps.insert(i + 1, _steps.removeAt(i))),
            ),
            IconButton(
              tooltip: tr('edit.removeStep'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => setState(() => _steps.removeAt(i).text.dispose()),
            ),
          ]),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextField(
              controller: s.text,
              minLines: 2,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: tr('edit.stepHint')),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 86,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in s.photos)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: RecipePhoto(photoId: p, recipe: r, width: 110, height: 86),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () => setState(() => s.photos.remove(p)),
                        child: const CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.black54,
                          child: Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ]),
                ),
              InkWell(
                onTap: _busyPhoto ? null : () => _addStepPhotos(s),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 110,
                  decoration: BoxDecoration(
                    border: Border.all(color: nb.line, width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _busyPhoto
                      ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.add_a_photo_outlined, color: scheme.primary),
                          const SizedBox(height: 4),
                          Text(tr('edit.addPhotos'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                        ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
