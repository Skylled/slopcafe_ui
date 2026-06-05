import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../l10n/l10n.dart';
import '../providers/document_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/section_header.dart';
import '../widgets/toast.dart';

/// Markdown composition / authoring screen — the operator-facing front end for
/// `POST /admin/documents` (the backend's new authoring surface).
///
/// This is intentionally a **forkable starting point**. The plumbing is wired
/// end-to-end against the real contract: the metadata form, the `format`
/// toggle, the write/preview switch, the POST call, sanitizer-aware result
/// handling, and navigation all work. What is *deliberately* left open is the
/// actual Markdown/HTML rendering — see [_PreviewPane], a single isolated
/// widget you can drop a renderer package into (flutter_markdown,
/// markdown_widget, gpt_markdown, an HTML widget, …) to evaluate it without
/// touching anything else on the screen.
///
/// Pops with the backend's [WriteResponse] on success so the caller can surface
/// the outcome; the canonical document list is already reloaded by
/// [DocumentsListNotifier.authorDocument] before the pop.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

/// Body format accepted by the authoring endpoint (the `format` field).
enum _Format {
  markdown('markdown'),
  html('html');

  const _Format(this.wire);
  final String wire;
}

/// Compose view mode — edit the source vs. preview the render.
enum _Mode { write, preview }

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _content = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _tags = TextEditingController();
  final _slug = TextEditingController();

  _Format _format = _Format.markdown;
  _Mode _mode = _Mode.write;

  /// `null` = omit `visibility` from the request (let the deploy default decide);
  /// otherwise the wire value `'public'` / `'private'`.
  String? _visibility;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Keep the preview live while the operator types in it.
    _content.addListener(_onContentChanged);
  }

  void _onContentChanged() {
    if (_mode == _Mode.preview && mounted) setState(() {});
  }

  @override
  void dispose() {
    _content.removeListener(_onContentChanged);
    _content.dispose();
    _title.dispose();
    _description.dispose();
    _tags.dispose();
    _slug.dispose();
    super.dispose();
  }

  List<String> get _parsedTags => _tags.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _publish() async {
    final l10n = context.l10n;
    if (_content.text.trim().isEmpty) {
      showToast(context, l10n.composeContentRequired, danger: true);
      setState(() => _mode = _Mode.write);
      return;
    }

    setState(() => _submitting = true);
    try {
      final write = await ref
          .read(documentsListProvider.notifier)
          .authorDocument(
            content: _content.text,
            format: _format.wire,
            title: _title.text.trim(),
            description: _description.text.trim(),
            tags: _parsedTags,
            slug: _slug.text.trim(),
            visibility: _visibility,
          );
      if (!mounted) return;
      Navigator.of(context).pop(write);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showToast(context, l10n.failedPublish(ApiError.describe(e)), danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            12,
            AppSpacing.screenH,
            AppSpacing.bottomInset,
          ),
          children: [
            BackHeader(l10n.composeTitle, eyebrow: l10n.composeEyebrow),
            const SizedBox(height: 18),

            // Toolbar — write/preview mode + content format.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _SegToggle<_Mode>(
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                  options: [
                    (_Mode.write, l10n.composeModeWrite),
                    (_Mode.preview, l10n.composeModePreview),
                  ],
                ),
                _SegToggle<_Format>(
                  value: _format,
                  onChanged: _submitting
                      ? null
                      : (f) => setState(() => _format = f),
                  options: [
                    (_Format.markdown, l10n.composeFormatMarkdown),
                    (_Format.html, l10n.composeFormatHtml),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Source editor / rendered preview.
            if (_mode == _Mode.write)
              _Editor(
                controller: _content,
                enabled: !_submitting,
                hint: l10n.composeBodyHint,
              )
            else
              _PreviewPane(source: _content.text, format: _format),
            const SizedBox(height: 24),

            // ---- Metadata ----
            SectionHeader(l10n.composeDetails),
            _Field(
              label: l10n.composeTitleLabel,
              controller: _title,
              enabled: !_submitting,
              hint: l10n.composeTitleHint,
            ),
            _Field(
              label: l10n.composeDescriptionLabel,
              controller: _description,
              enabled: !_submitting,
              hint: l10n.composeDescriptionHint,
              minLines: 2,
              maxLines: 4,
            ),
            _Field(
              label: l10n.tagsLabel,
              controller: _tags,
              enabled: !_submitting,
              hint: l10n.tagsHint,
            ),
            _Field(
              label: l10n.slugLabel,
              controller: _slug,
              enabled: !_submitting,
              hint: l10n.slugHint,
              note: l10n.composeSlugNote,
            ),

            Text(
              l10n.composeVisibilityLabel,
              style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
            ),
            const SizedBox(height: 8),
            _SegToggle<String?>(
              value: _visibility,
              expand: true,
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _visibility = v),
              options: <(String?, String)>[
                (null, l10n.composeVisibilityDefault),
                ('public', l10n.composeVisibilityPublic),
                ('private', l10n.composeVisibilityPrivate),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.composeVisibilityNote,
              style: AppText.small.copyWith(color: c.textFaint),
            ),
            const SizedBox(height: 24),

            AppButton(
              _submitting ? l10n.composePublishing : l10n.composePublish,
              variant: AppBtnVariant.primary,
              icon: Icons.send_rounded,
              expand: true,
              onPressed: _submitting ? null : _publish,
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// PREVIEW SEAM — the swap point for a Markdown / HTML renderer.
//
// This baseline ships NO rendering dependency on purpose: it shows the raw
// source so the screen is useful immediately and so different packages can be
// A/B'd here in isolation. To evaluate one, replace the body branch below with
// e.g. `Markdown(data: source)` (flutter_markdown), `GptMarkdown(source)`,
// `MarkdownWidget(data: source)`, or an HTML renderer when [format] is html.
// Nothing else in this screen needs to change.
// ===========================================================================
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.source, required this.format});

  final String source;
  final _Format format;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final isEmpty = source.trim().isEmpty;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 300),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('${l10n.composePreviewRaw} · ${format.wire}'),
          const SizedBox(height: 12),
          if (isEmpty)
            Text(
              l10n.composePreviewEmpty,
              style: AppText.body.copyWith(
                color: c.textFaint,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            // Raw passthrough — replace with a real renderer (see header above).
            SelectableText(
              source,
              style: AppText.mono.copyWith(
                fontSize: 13,
                color: c.textDim,
                height: 1.55,
              ),
            ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Small composition primitives (local to this screen).
// ===========================================================================

/// The large, monospaced source editor that fills the screen and grows with
/// the content.
class _Editor extends StatelessWidget {
  const _Editor({
    required this.controller,
    required this.enabled,
    required this.hint,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: c.shadow,
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: 14,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        cursorColor: c.clay,
        style: AppText.mono.copyWith(fontSize: 13.5, color: c.text, height: 1.55),
        decoration: InputDecoration.collapsed(
          hintText: hint,
          hintStyle: AppText.mono.copyWith(fontSize: 13.5, color: c.textFaint),
        ),
      ),
    );
  }
}

/// A labelled text field (label · field · optional note), matching the Operate
/// edit-sheet fields.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.enabled,
    this.hint,
    this.note,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final String? hint;
  final String? note;
  final int minLines;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            enabled: enabled,
            minLines: minLines,
            maxLines: maxLines,
            textCapitalization: TextCapitalization.sentences,
            style: AppText.body.copyWith(color: c.text),
            decoration: InputDecoration(hintText: hint),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: AppText.small.copyWith(color: c.textFaint)),
          ],
        ],
      ),
    );
  }
}

/// A compact pill-style segmented control. [expand] makes the segments share
/// the full width equally (used for the visibility row); otherwise it hugs its
/// content. Pass a null [onChanged] to disable it.
class _SegToggle<T> extends StatelessWidget {
  const _SegToggle({
    required this.value,
    required this.onChanged,
    required this.options,
    this.expand = false,
  });

  final T value;
  final ValueChanged<T>? onChanged;
  final List<(T, String)> options;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final segments = [
      for (final (opt, label) in options)
        if (expand)
          Expanded(child: _seg(context, opt, label))
        else
          _seg(context, opt, label),
    ];
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.lineSoft),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: segments,
        ),
      ),
    );
  }

  Widget _seg(BuildContext context, T opt, String label) {
    final c = context.colors;
    final active = opt == value;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(opt),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: active ? c.shadow : null,
        ),
        child: Text(
          label,
          style: AppText.title.copyWith(
            fontSize: 13,
            color: active ? c.clayD : c.textDim,
          ),
        ),
      ),
    );
  }
}
