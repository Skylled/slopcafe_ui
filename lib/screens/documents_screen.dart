import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/document.dart';
import '../providers/document_provider.dart';
import 'document_detail_screen.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  // Navigation / View Modes: list vs search
  bool _isSearchMode = false;

  // Local state filters
  String? _selectedTag;
  final _slugController = TextEditingController();
  bool _includeRevoked = true;

  // Search parameters & debouncing
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounceTimer;

  // Scroll controllers for pagination
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    
    // Fetch initial list page on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadList(clear: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _slugController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_isSearchMode) return; // Search results are not paginated
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadList();
    }
  }

  void _loadList({bool clear = false}) {
    ref.read(documentsListProvider.notifier).loadNextPage(
          tag: _selectedTag,
          slug: _slugController.text.trim(),
          clear: clear,
        );
  }

  void _onSearchChanged(String text) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      setState(() {
        _searchQuery = text;
      });
    });
  }

  void _applyFilters() {
    if (_isSearchMode) {
      // For search mode, changing filters immediately updates future provider query
      setState(() {});
    } else {
      _loadList(clear: true);
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedTag = null;
      _slugController.clear();
      _includeRevoked = true;
      _searchController.clear();
      _searchQuery = '';
    });
    _loadList(clear: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listState = ref.watch(documentsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_isSearchMode) {
                setState(() {});
              } else {
                _loadList(clear: true);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_off_outlined),
            tooltip: 'Clear Filters',
            onPressed: _resetFilters,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Core Header visual Mode Toggle: List vs Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.list_alt_rounded),
                        label: Text('List Fleet'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.search_rounded),
                        label: Text('Deep Search'),
                      ),
                    ],
                    selected: {_isSearchMode},
                    onSelectionChanged: (value) {
                      setState(() {
                        _isSearchMode = value.first;
                      });
                    },
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: theme.colorScheme.primaryContainer,
                      selectedForegroundColor: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Filter Shelf UI
          _buildFilterShelf(listState.aggregatedTags),

          // 3. Search Bar if Search Mode is active
          if (_isSearchMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Enter keyword or body content...',
                leading: const Icon(Icons.search),
                onChanged: _onSearchChanged,
                elevation: WidgetStateProperty.all(0.0),
                backgroundColor: WidgetStateProperty.all(
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

          // 4. Main Body Content
          Expanded(
            child: _isSearchMode ? _buildSearchResultsView() : _buildListView(listState),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterShelf(Set<String> allTags) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.surfaceContainerHighest,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextFormField(
                    controller: _slugController,
                    decoration: InputDecoration(
                      hintText: 'Filter by slug exact match...',
                      labelText: 'Slug Filter',
                      prefixIcon: const Icon(Icons.bookmark_outline, size: 20),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      suffixIcon: _slugController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () {
                                _slugController.clear();
                                _applyFilters();
                              },
                            )
                          : null,
                    ),
                    onFieldSubmitted: (_) => _applyFilters(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Include Revoked',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: _includeRevoked,
                      onChanged: (val) {
                        setState(() {
                          _includeRevoked = val;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (allTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Filter by Tag:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: allTags.map((tag) {
                  final isSelected = _selectedTag == tag;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      label: Text(tag),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedTag = selected ? tag : null;
                        });
                        _applyFilters();
                      },
                      selectedColor: theme.colorScheme.secondaryContainer,
                      checkmarkColor: theme.colorScheme.onSecondaryContainer,
                    ),
                  );
                }).toList(),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildListView(DocumentsListState state) {
    final theme = Theme.of(context);

    // Apply local client side "Include Revoked" filter
    final List<DocumentListing> docs = _includeRevoked
        ? state.documents
        : state.documents.where((doc) => !doc.isRevoked).toList();

    if (docs.isEmpty && !state.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No documents found.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _resetFilters,
              child: const Text('Reset All Filters'),
            )
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _loadList(clear: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: docs.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == docs.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final doc = docs[index];
          return _buildDocumentRow(doc);
        },
      ),
    );
  }

  Widget _buildDocumentRow(DocumentListing doc) {
    final theme = Theme.of(context);
    final sizeFormatted = doc.isRevoked ? '0 B' : '${doc.currentSize ?? 0} B';
    final dateStr = DateFormat.yMMMd().add_jm().format(doc.createdAt.toLocal());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocumentDetailScreen(document: doc),
            ),
          );
          if (result == true) {
            // Document was revoked in details screen, refresh the list
            _loadList(clear: true);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      doc.title ?? '[Untitled]',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: doc.isRevoked ? theme.colorScheme.onSurfaceVariant : null,
                        decoration: doc.isRevoked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (doc.isRevoked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'REVOKED',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (doc.description != null && doc.description!.trim().isNotEmpty) ...[
                Text(
                  doc.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildMetaChip(
                    Icons.bookmark_outline,
                    doc.slug ?? '—',
                    theme.colorScheme.primary,
                  ),
                  _buildMetaChip(
                    Icons.layers_outlined,
                    doc.isRevoked ? 'v—' : 'v${doc.currentVer}',
                    theme.colorScheme.secondary,
                  ),
                  _buildMetaChip(
                    Icons.save_outlined,
                    sizeFormatted,
                    theme.colorScheme.tertiary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: theme.colorScheme.surfaceContainerHighest, height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'by ${doc.createdByName ?? 'Unknown Agent'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    dateStr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, Color color) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsView() {
    if (_searchQuery.trim().length < 2) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.manage_search, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'Enter at least 2 characters to search...',
              style: TextStyle(fontSize: 16),
            ),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final searchResultsAsync = ref.watch(
      documentSearchProvider(
        SearchQueryParams(
          query: _searchQuery,
          tag: _selectedTag,
          slug: _slugController.text.trim(),
        ),
      ),
    );

    return searchResultsAsync.when(
      data: (hits) {
        // Filter revoked client side based on includeRevoked setting
        final filteredHits = _includeRevoked
            ? hits
            : hits.where((hit) => !hit.document.isRevoked).toList();

        if (filteredHits.isEmpty) {
          return const Center(
            child: Text('No search matches found.'),
          );
        }

        // Find max score in current set for normalization of relevance bar
        final maxScore = filteredHits.isEmpty
            ? 1.0
            : filteredHits.map((h) => h.score).reduce((a, b) => a > b ? a : b);

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filteredHits.length + (filteredHits.length >= 50 ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == filteredHits.length) {
              return Card(
                color: theme.colorScheme.surfaceContainerHighest,
                margin: const EdgeInsets.symmetric(vertical: 16),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(Icons.info_outline, size: 32),
                      SizedBox(height: 8),
                      Text(
                        'Showing top 50 results. If your document is not here, refine your search query.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              );
            }

            final hit = filteredHits[index];
            return _buildSearchHitRow(hit, maxScore);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Search Error: ${err.toString()}',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchHitRow(SearchHit hit, double maxScore) {
    final theme = Theme.of(context);
    final doc = hit.document;
    final dateStr = DateFormat.yMMMd().format(doc.createdAt.toLocal());

    // Relevance score calculation (normalized 0.0 - 1.0)
    final relativeScore = maxScore > 0 ? (hit.score / maxScore) : 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DocumentDetailScreen(document: doc),
            ),
          );
          if (result == true) {
            setState(() {}); // refresh search futures
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title / Metadata Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      doc.title ?? '[Untitled]',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: doc.isRevoked ? theme.colorScheme.onSurfaceVariant : null,
                        decoration: doc.isRevoked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (doc.isRevoked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'REVOKED',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),

              // Relevance Metric bar
              Row(
                children: [
                  Text(
                    'Relevance: ',
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: relativeScore,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        color: theme.colorScheme.primary,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(relativeScore * 100).toInt()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Matched Field Chip + Snippet View
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Match: ${hit.matchedField.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // RichText snippet parsing runs inside [match_word]
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RichText(
                  text: TextSpan(
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    children: _parseSnippet(hit.snippet, theme.colorScheme),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'by ${doc.createdByName ?? 'Unknown Agent'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    dateStr,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TextSpan> _parseSnippet(String snippet, ColorScheme colorScheme) {
    final List<TextSpan> spans = [];
    final RegExp regExp = RegExp(r'\[(.*?)\]');
    int start = 0;

    for (final match in regExp.allMatches(snippet)) {
      if (match.start > start) {
        spans.add(TextSpan(text: snippet.substring(start, match.start)));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
        ),
      ));
      start = match.end;
    }

    if (start < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(start)));
    }

    return spans;
  }
}
