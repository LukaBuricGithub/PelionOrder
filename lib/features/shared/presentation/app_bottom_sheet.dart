import 'package:flutter/material.dart';

import 'bottom_sheet_safe_area.dart';

/// A modal bottom-sheet "drawer" with a branded blue header (grab handle +
/// title + close), a scrollable body, and an optional action footer. Ported
/// verbatim from the ikasa app so create/edit flows share its look.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  String? title,
  Widget? body,
  Widget? footer,
  WidgetBuilder? sheetBuilder,
}) {
  assert(
    sheetBuilder != null || (title != null && body != null),
    'Provide either sheetBuilder or both title and body.',
  );

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (ctx) {
      if (sheetBuilder != null) return sheetBuilder(ctx);

      return AppBottomSheetScaffold(
        title: title!,
        body: body!,
        footer: footer,
      );
    },
  );
}

class AppBottomSheetScaffold extends StatelessWidget {
  const AppBottomSheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.footer,
    this.footerDivider = true,
  });

  final String title;
  final Widget body;
  final Widget? footer;

  /// Whether to draw the hairline divider between the body and the footer.
  final bool footerDivider;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final bottomClearance = bottomSheetSafePadding(context, minimum: 56);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: cs.primary,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Zatvori',
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: body,
              ),
            ),
            if (footer != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: footerDivider
                      ? Border(
                          top: BorderSide(
                            color: cs.outlineVariant.withValues(alpha: 0.45),
                          ),
                        )
                      : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: footer,
                ),
              ),
            SizedBox(height: bottomClearance),
          ],
        ),
      ),
    );
  }
}
