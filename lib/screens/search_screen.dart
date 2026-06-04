import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../models/document.dart';
import '../providers/document_provider.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import 'reader_screen.dart';

/// Search tab — "Search the whole café": an autofocus query field, debounced
/// live results, and relevance-ranked hit cards with highlighted snippets.
///
/// Wiring is ported verbatim from the old `DocumentsScreen` search slice
/// (`documentSearchProvider` + `SearchQueryParams`, the snippet `[bracket]`
/// parser, and the score/maxScore relevance normalization). The provider keeps
/// its own local-cache fallback, so we never bypass it.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// The committed (debounced) query that actually drives the provider.
  String _searchQuery = '';
  Timer? _debounceTimer;

  /// Static seed suggestions, blended with a couple of real aggregated tags.
  static const List<String> _staticSuggestions = [
    'sanitizer',
    'recipe',
    'oauth',
    'espresso',
    'revoke',
  ];

  @override
  void initState() {
    super.initState();
    // Autofocus the field shortly after entrance (matches the mockup's 200ms).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = text;
      });
    });
  }

  void _setQuery(String value) {
    _debounceTimer?.cancel();
    _searchController.text = value;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: value.length),
    );
    setState(() {
      _searchQuery = value;
    });
    _focusNode.requestFocus();
  }

  void _clear() {
    _debounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
    });
    _focusNode.requestFocus();
  }

  Future<void> _openDoc(DocumentListing doc) async {
    // The reader pops `true` when it mutates a document (revoke / visibility /
    // slug / tags). Re-run the search so results don't show stale state.
    final changed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
    if (changed == true && mounted) {
      ref.invalidate(documentSearchProvider);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topInset = MediaQuery.paddingOf(context).top + 12;
    final searching = _searchQuery.trim().length >= 2;

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          // ---- Title + search field (fixed header) ----
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              topInset,
              AppSpacing.screenH,
              12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search',
                  style: AppText.display.copyWith(fontSize: 32, color: c.text),
                ),
                const SizedBox(height: 14),
                _SearchField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  active: searching,
                  onChanged: _onSearchChanged,
                  onClear: _clear,
                ),
              ],
            ),
          ),

          // ---- Body (scrolling results / suggestions) ----
          Expanded(
            child: searching
                ? _buildResults(_searchQuery)
                : _buildSuggestions(),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- body

  Widget _buildSuggestions() {
    final c = context.colors;
    // A few static seeds plus a couple of real tags from what we've loaded.
    final tags = ref.watch(
      documentsListProvider.select((s) => s.aggregatedTags),
    );
    final tagSuggestions = tags
        .where((t) => t.trim().isNotEmpty && !_staticSuggestions.contains(t))
        .take(2)
        .toList();
    final suggestions = [..._staticSuggestions, ...tagSuggestions];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        6,
        AppSpacing.screenH,
        AppSpacing.bottomInset,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
            child: Text(
              'TRY SEARCHING',
              style: AppText.label.copyWith(
                fontSize: 12.5,
                letterSpacing: 0.8,
                color: c.textFaint,
              ),
            ),
          ),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final s in suggestions)
                _SuggestionChip(label: s, onTap: () => _setQuery(s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResults(String query) {
    final c = context.colors;
    final resultsAsync = ref.watch(
      documentSearchProvider(SearchQueryParams(query: query)),
    );

    return resultsAsync.when(
      data: (hits) {
        if (hits.isEmpty) {
          return _EmptyState(query: query.trim());
        }

        // Normalize the relevance bar against the strongest hit in the set
        // (ported from the old screen's maxScore logic).
        final maxScore = hits
            .map((h) => h.score)
            .fold<double>(0, (a, b) => a > b ? a : b);

        // The backend caps at 50; surface a refine hint when we hit the ceiling.
        final showCeilingHint = hits.length >= 50;

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            6,
            AppSpacing.screenH,
            AppSpacing.bottomInset,
          ),
          itemCount: hits.length + (showCeilingHint ? 2 : 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 2, 14),
                child: Text(
                  '${hits.length} result${hits.length == 1 ? '' : 's'} · ranked by relevance',
                  style: AppText.small.copyWith(color: c.textFaint),
                ),
              );
            }

            final hitIndex = index - 1;
            if (showCeilingHint && hitIndex == hits.length) {
              return _CeilingHint();
            }

            final hit = hits[hitIndex];
            final rel = maxScore > 0 ? (hit.score / maxScore) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: RiseIn(
                delay: Duration(milliseconds: (hitIndex * 40).clamp(0, 250)),
                child: _SearchHitCard(
                  hit: hit,
                  relevance: rel,
                  onOpen: () => _openDoc(hit.document),
                ),
              ),
            );
          },
        );
      },
      loading: () => const _LoadingState(),
      error: (err, _) => _ErrorState(message: err.toString()),
    );
  }
}

// ===================================================================== field

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.active,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool active;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: active ? c.clay : c.line),
        boxShadow: active ? c.glow : c.shadow,
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: active ? c.clayD : c.textFaint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: c.clayD,
              style: AppText.bodyLg.copyWith(fontSize: 16, color: c.text),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                hintText: 'Titles, body, tags, slugs…',
                hintStyle: AppText.bodyLg.copyWith(
                  fontSize: 16,
                  color: c.textFaint,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 18, color: c.textFaint),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================ suggestion chip

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressCard(
      onPress: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(color: c.line),
          boxShadow: c.shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 13, color: c.textFaint),
            const SizedBox(width: 7),
            Text(
              label,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: c.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================== hit card

class _SearchHitCard extends StatelessWidget {
  const _SearchHitCard({
    required this.hit,
    required this.relevance,
    required this.onOpen,
  });

  final SearchHit hit;
  final double relevance;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final doc = hit.document;
    final author = (doc.createdByName?.trim().isNotEmpty ?? false)
        ? doc.createdByName!
        : '—';
    final pct = (relevance * 100).round();

    return PressCard(
      onPress: onOpen,
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadii.xl + 1),
          border: Border.all(color: c.lineSoft),
          boxShadow: c.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top row: author + matched-field pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 14, color: c.textFaint),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small.copyWith(color: c.textFaint),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Pill(
                  hit.matchedField.toUpperCase(),
                  tone: PillTone.clay,
                  small: true,
                ),
              ],
            ),
            const SizedBox(height: 7),

            // title + relevance percentage
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    doc.title ?? '[Untitled]',
                    style: AppText.titleSerif.copyWith(
                      fontSize: 20,
                      color: doc.isRevoked ? c.textFaint : c.text,
                      decoration: doc.isRevoked
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text.rich(
                  TextSpan(
                    text: '$pct',
                    style: AppText.titleSerif.copyWith(
                      fontSize: 20,
                      color: c.clayD,
                    ),
                    children: [
                      TextSpan(
                        text: '%',
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),

            // gradient relevance bar
            _RelevanceBar(value: relevance),
            const SizedBox(height: 11),

            // highlighted snippet
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Text.rich(
                TextSpan(
                  style: AppText.small.copyWith(
                    fontSize: 13,
                    height: 1.55,
                    color: c.textDim,
                  ),
                  children: _buildSnippetSpans(context, hit.snippet),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Parses the snippet's `[bracketed]` match spans into honey-highlighted
  /// `mark` runs (ported from the old `_parseSnippet`).
  List<InlineSpan> _buildSnippetSpans(BuildContext context, String snippet) {
    final c = context.colors;
    final List<InlineSpan> spans = [];
    final RegExp regExp = RegExp(r'\[(.*?)\]');
    int start = 0;

    for (final match in regExp.allMatches(snippet)) {
      if (match.start > start) {
        spans.add(TextSpan(text: snippet.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: c.text,
            backgroundColor: c.honey.withValues(alpha: 0.40),
          ),
        ),
      );
      start = match.end;
    }

    if (start < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(start)));
    }

    return spans;
  }
}

class _RelevanceBar extends StatelessWidget {
  const _RelevanceBar({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 4,
        color: c.surface3,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.clayD, c.clay]),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================ stateful states

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        60,
        AppSpacing.screenH,
        AppSpacing.bottomInset,
      ),
      child: Column(
        children: [
          Icon(Icons.search, size: 30, color: c.textFaint),
          const SizedBox(height: 12),
          Text(
            'Nothing matches “$query”.',
            textAlign: TextAlign.center,
            style: AppText.titleSerif.copyWith(fontSize: 20, color: c.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different keyword, tag, or slug.',
            textAlign: TextAlign.center,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.bottomInset),
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: c.clay),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        60,
        AppSpacing.screenH,
        AppSpacing.bottomInset,
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 30, color: c.red),
          const SizedBox(height: 12),
          Text(
            'Search hit a snag.',
            textAlign: TextAlign.center,
            style: AppText.titleSerif.copyWith(fontSize: 20, color: c.text),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
        ],
      ),
    );
  }
}

class _CeilingHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_outlined, size: 18, color: c.honeyD),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Showing the top 50 plates. Refine your search to find the rest.',
              style: AppText.small.copyWith(color: c.textDim),
            ),
          ),
        ],
      ),
    );
  }
}
