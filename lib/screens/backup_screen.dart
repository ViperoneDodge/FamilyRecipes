import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import '../main.dart';
import '../services/backup_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Copie complete delle ricette: create a mano o in automatico (prima di importare o ripristinare),
/// da ripristinare, salvare in un file o condividere.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  List<BackupInfo> _list = const [];
  bool _busy = false;

  String get _user => appState.session?.storageKey ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await BackupService.list(_user);
      if (mounted) setState(() => _list = l);
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  String _reason(String r) => switch (r) {
        'import' => tr('backup.reasonImport'),
        'restore' => tr('backup.reasonRestore'),
        _ => tr('backup.reasonManual'),
      };

  String _when(DateTime d) => '${fmtDate(d)} ${DateFormat('HH:mm').format(d)}';

  Future<void> _create() => _run(() async {
        final f = await appState.backupNow();
        if (mounted) showSnack(context, f == null ? tr('backup.failed') : tr('backup.created'));
      });

  Future<void> _restore(BackupData data, [File? from]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('backup.restoreTitle')),
        content: Text(tr('backup.restoreText')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('backup.restore'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final n = await appState.restoreBackup(data, from: from);
      if (mounted) showSnack(context, tr('backup.restored', {'n': n}));
    });
  }

  Future<void> _restoreFile(BackupInfo b) async {
    setState(() => _busy = true);
    final r = await BackupService.readFile(b.file.path);
    if (mounted) setState(() => _busy = false);
    if (r.data == null) {
      if (mounted) showSnack(context, '${tr('backup.badFile')} (${r.why})');
      return;
    }
    await _restore(r.data!, b.file);
  }

  Future<void> _share(BackupInfo b) => _run(() async {
        await SharePlus.instance.share(ShareParams(files: [XFile(b.file.path, mimeType: 'application/json')]));
      });

  Future<void> _saveAs(BackupInfo b) => _run(() async {
        final bytes = await b.file.readAsBytes();
        final path = await FilePicker.saveFile(fileName: b.name, bytes: bytes);
        if (path != null && mounted) showSnack(context, tr('backup.saved'));
      });

  Future<void> _delete(BackupInfo b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('backup.deleteTitle')),
        content: Text('${_when(b.at)} · ${tr('backup.recipes', {'n': b.recipes})}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('common.delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      if (await b.file.exists()) await b.file.delete();
    });
  }

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(type: FileType.any, withData: false);
    final f = res?.files.single;
    if (f == null) return;
    if (mounted) setState(() => _busy = true);
    ({BackupData? data, String why}) r = (data: null, why: '-');
    try {
      if (f.path != null) {
        r = await BackupService.readFile(f.path!);
      } else if (f.bytes != null) {
        r = await BackupService.readBytes(f.bytes!);
      }
    } catch (e) {
      r = (data: null, why: '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (r.data == null) {
      if (mounted) showSnack(context, '${tr('backup.badFile')} (${r.why})');
      return;
    }
    await _restore(r.data!);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TableclothBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(tr('backup.title'))),
        body: NotebookPage(
          child: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
              children: [
                Text(tr('backup.info')),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.backup_outlined),
                    label: Text(tr('backup.create')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pick,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(tr('backup.loadFile')),
                  ),
                ]),
                if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                const SizedBox(height: 16),
                if (_list.isEmpty) Text(tr('backup.none'), style: TextStyle(color: scheme.onSurfaceVariant)),
                for (final b in _list)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_when(b.at), style: Theme.of(context).textTheme.titleMedium),
                        Text('${_reason(b.reason)} · ${tr('backup.recipes', {'n': b.recipes})}',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Wrap(spacing: 4, runSpacing: 4, children: [
                          TextButton.icon(
                            onPressed: () => _restoreFile(b),
                            icon: const Icon(Icons.restore),
                            label: Text(tr('backup.restore')),
                          ),
                          TextButton.icon(
                            onPressed: () => _saveAs(b),
                            icon: const Icon(Icons.download_outlined),
                            label: Text(tr('backup.save')),
                          ),
                          TextButton.icon(
                            onPressed: () => _share(b),
                            icon: const Icon(Icons.share_outlined),
                            label: Text(tr('backup.share')),
                          ),
                          TextButton.icon(
                            onPressed: () => _delete(b),
                            icon: const Icon(Icons.delete_outline),
                            label: Text(tr('common.delete')),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(tr('backup.outside'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
