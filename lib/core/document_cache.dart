import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import '../api/api.dart';

class DocumentCacheManager {
  static Future<Directory> get _cacheDir async {
    final tempDir = await getTemporaryDirectory();
    final cachePath = '${tempDir.path}/slopcafe_doc_cache';
    final dir = Directory(cachePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
