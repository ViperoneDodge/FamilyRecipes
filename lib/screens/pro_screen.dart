import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

void openPro(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProScreen()));

/// Spiega perché serve Pro e offre di scoprirlo.
Future<void> showProOffer(BuildContext context, String reason) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.workspace_premium_outlined),
      title: Text(tr('pro.section')),
      content: Text(reason),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('pro.discover'))),
      ],
    ),
  );
  if (go == true && context.mounted) openPro(context);
}

String proLimitReason() => tr('pro.reasonLimit', {'n': AppState.freeLimit});

/// Striscia sotto la barra in alto per le ricette oltre i limiti della versione gratuita.
PreferredSizeWidget proReadOnlyBar(BuildContext context) {
  final nb = NotebookColors.of(context);
  return PreferredSize(
    preferredSize: const Size.fromHeight(40),
    child: Material(
      color: nb.paper,
      child: InkWell(
        onTap: () => openPro(context),
        child: SizedBox(
          height: 40,
          child: Row(children: [
            const SizedBox(width: 12),
            Icon(Icons.lock_outline, size: 18, color: nb.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('pro.readOnly'),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: nb.ink)),
            ),
            Icon(Icons.chevron_right, color: nb.accent),
            const SizedBox(width: 8),
          ]),
        ),
      ),
    ),
  );
}

/// Riquadro "disponibile con Pro" (categorie bloccate, suggerimento dello chef).
class ProTeaser extends StatelessWidget {
  final IconData icon;
  final String text;
  const ProTeaser({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final nb = NotebookColors.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 28, color: nb.accent),
            const SizedBox(width: 6),
            Icon(Icons.lock_outline, size: 22, color: nb.accent),
          ]),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => openPro(context),
            icon: const Icon(Icons.workspace_premium_outlined),
            label: Text(tr('pro.groupLockedBtn')),
          ),
        ]),
      ),
    );
  }
}

class ProScreen extends StatelessWidget {
  const ProScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final pro = appState.pro;
        final product = pro.product;
        final scheme = Theme.of(context).colorScheme;
        final nb = NotebookColors.of(context);
        final benefits = [
          (Icons.category_outlined, tr('pro.benefitCategories')),
          (Icons.all_inclusive, tr('pro.benefitUnlimited')),
          (Icons.soup_kitchen_outlined, tr('pro.benefitChef')),
          (Icons.calendar_month_outlined, tr('pro.benefitPlan')),
          (Icons.favorite_outline, tr('pro.benefitSupport')),
        ];
        return TableclothBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(title: Text(tr('pro.section'))),
            body: NotebookPage(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 20, 16, 24), children: [
                Icon(appState.isPro ? Icons.verified : Icons.workspace_premium_outlined, size: 56, color: nb.accent),
                const SizedBox(height: 8),
                Text(
                  appState.isPro ? tr('pro.active') : tr('pro.title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: handFont, fontSize: 28, color: nb.ink),
                ),
                const SizedBox(height: 4),
                Text(tr('pro.subtitle'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                for (final (icon, text) in benefits)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(icon, color: nb.accent),
                    title: Text(text),
                  ),
                const SizedBox(height: 8),
                Text(
                    tr('pro.freeInfo', {
                      'n': AppState.freeLimit,
                      'cats': AppState.freeCategories.map(categoryLabel).join(', '),
                    }),
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 20),
                if (appState.isPro)
                  Text(appState.devPro && !appState.purchasedPro ? tr('pro.activeDev') : tr('pro.activeThanks'),
                      textAlign: TextAlign.center)
                else ...[
                  FilledButton.icon(
                    onPressed: pro.busy || product == null
                        ? null
                        : () async {
                            final ok = await pro.buy();
                            if (!ok && context.mounted) {
                              showSnack(context, pro.lastError ?? tr('pro.unavailable'));
                            }
                          },
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    icon: pro.busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.shopping_bag_outlined),
                    label: Text(product == null ? tr('pro.buy') : tr('pro.buyPrice', {'price': product.price})),
                  ),
                  if (product == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(tr('pro.unavailable'),
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: pro.storeAvailable
                        ? () async {
                            await pro.restore();
                            if (context.mounted) showSnack(context, tr('pro.restoring'));
                          }
                        : null,
                    child: Text(tr('pro.restore')),
                  ),
                  Text(tr('pro.oneTime'),
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}
