import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../api/api.dart';
import 'secure_storage.dart';

/// The offline document cache — rendered HTML by `public_id`, plus the default
/// document list.
///
/// ## Why every path goes through a per-instance namespace
///
/// A `public_id` is a fact about *one* deployment. Two Slopcafe instances can
/// legitimately mint the same id for entirely different documents, so a single
/// flat cache shared across instances would serve one deployment's bytes under
/// the other's name — silently, and only for documents whose ids happened to
/// collide. Every file therefore lives under `slopcafe_doc_cache/<instance-id>/`,
/// where the namespace is [SlopcafeInstance.id] (see `instances.dart`).
///
/// Namespacing rather than wiping on switch is deliberate too: switching back to
/// an instance finds its cache intact, which is the whole point of a cache for
/// an operator who moves between deployments all day.
class DocumentCacheManager {
  /// The namespace used when no instance is active. Only reachable in the
  /// window before first-run setup completes, where nothing is cached anyway.
  static const String _unscopedNamespace = 'default';

  /// One-shot guard for [_pruneLegacyLayout].
  static bool _prunedLegacyLayout = false;

  /// The cache root, shared by every instance.
  static Future<Directory> get _cacheRoot async {
    final tempDir = await getTemporaryDirectory();
    return Directory('${tempDir.path}/slopcafe_doc_cache');
  }

  /// The active instance's cache directory, created on demand.
  static Future<Directory> get _cacheDir async {
    final root = await _cacheRoot;
    await _pruneLegacyLayout(root);
    final namespace =
        await SecureStorageService.instance.getActiveInstanceId() ??
        _unscopedNamespace;
    final dir = Directory('${root.path}/$namespace');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Delete the loose files a pre-multi-instance build left directly in the
  /// cache root, once per process.
  ///
  /// Those files belong to the deployment that became the first migrated
  /// instance, but they are cached bytes in a temp directory — re-fetching them
  /// costs one request each, whereas hoisting them into a namespace costs code
  /// that would be dead the moment every install has upgraded. Directories are
  /// left alone: those are the namespaces.
  static Future<void> _pruneLegacyLayout(Directory root) async {
    if (_prunedLegacyLayout) return;
    _prunedLegacyLayout = true;
    try {
      if (!await root.exists()) return;
      for (final entity in root.listSync()) {
        if (entity is File) await entity.delete();
      }
    } catch (_) {
      // Best-effort: a cache we could not tidy is still a working cache.
    }
  }

  /// Drop every cached file for one instance — called when that instance is
  /// removed, or when its Base URL is edited to point somewhere else and its id
  /// therefore names a different deployment.
  static Future<void> deleteNamespace(String instanceId) async {
    try {
      final root = await _cacheRoot;
      final dir = Directory('${root.path}/$instanceId');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // Fail silently: an un-evicted cache is stale, not broken — every read
      // is version-keyed and revalidated.
    }
  }

  static Future<File> _getCacheFile(String publicId, int version) async {
    final dir = await _cacheDir;
    return File('${dir.path}/${publicId}_v$version.html');
  }

  /// Load cached HTML string for a specific document ID and version.
  /// Returns null if there is no cache hit.
  static Future<String?> getCachedHtml(String publicId, int version) async {
    try {
      final file = await _getCacheFile(publicId, version);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      // Return null on any error reading from disk
    }
    return null;
  }

  /// Write HTML string to disk, clobbering any existing cached versions
  /// of the same document to avoid stale cache.
  static Future<void> saveCachedHtml(
    String publicId,
    int version,
    String html,
  ) async {
    try {
      // Evict any old cached versions of this document before writing new one
      await deleteCachedDoc(publicId);

      final file = await _getCacheFile(publicId, version);
      await file.writeAsString(html);
    } catch (e) {
      // Fail silently if cache writing fails
    }
  }

  /// Evict all cache files for a given document publicId.
  static Future<void> deleteCachedDoc(String publicId) async {
    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = dir.listSync();
        for (var entity in entities) {
          if (entity is File && entity.path.contains(publicId)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // Fail silently if cache deletion fails
    }
  }

  /// Check if a specific version of a document is cached offline.
  static Future<bool> isCached(String publicId, int version) async {
    try {
      final file = await _getCacheFile(publicId, version);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// Find the version number of any cached HTML file for a given document publicId.
  /// Returns null if no cached file is found.
  static Future<int?> getCachedVersion(String publicId) async {
    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        final List<FileSystemEntity> entities = dir.listSync();
        final pattern = RegExp('^${RegExp.escape(publicId)}_v(\\d+)\\.html\$');
        for (var entity in entities) {
          if (entity is File) {
            final filename = entity.path.split(Platform.pathSeparator).last;
            final match = pattern.firstMatch(filename);
            if (match != null) {
              return int.tryParse(match.group(1) ?? '');
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save the default/unfiltered list of documents to disk.
  static Future<void> saveCachedDocumentList(
    List<DocumentListing> documents,
  ) async {
    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/documents_list.json');
      final jsonList = documents.map((d) => d.toJson()).toList();
      await file.writeAsString(json.encode(jsonList));
    } catch (_) {
      // Fail silently if cache writing fails
    }
  }

  /// Load the cached list of documents from disk.
  static Future<List<DocumentListing>?> getCachedDocumentList() async {
    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/documents_list.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = json.decode(content);
        return jsonList.map((j) => DocumentListing.fromJson(j)).toList();
      }
    } catch (_) {
      // Fail silently if cache reading fails
    }
    return null;
  }
}
