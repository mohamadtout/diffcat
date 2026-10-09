import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// A response kept for conditional requests: sent back as `If-None-Match`,
/// and returned when GitHub answers 304 Not Modified (which doesn't count
/// against the rate limit).
class EtagEntry {
  const EtagEntry({required this.etag, required this.data, this.link});

  final String etag;
  final Object? data;
  final String? link;
}

/// Where [GitHubClient] keeps ETags beyond its in-memory cache.
abstract interface class EtagCache {
  Future<EtagEntry?> read(String key);
  Future<void> write(String key, EtagEntry entry);
}

/// ETags on disk, one file per request, so the background notification check
/// (a fresh isolate every ~15 minutes) can make conditional requests: an
/// unchanged repo then costs no rate limit at all.
class FileEtagCache implements EtagCache {
  FileEtagCache(this.dir);

  final Directory dir;

  /// Files beyond this many are pruned, oldest first.
  static const maxEntries = 200;

  File _file(String key) => File('${dir.path}/${sha1.convert(utf8.encode(key))}.json');

  @override
  Future<EtagEntry?> read(String key) async {
    try {
      final j = jsonDecode(await _file(key).readAsString()) as Map<String, dynamic>;
      if (j['key'] != key) return null; // hash collision, however unlikely
      return EtagEntry(etag: j['etag'] as String, data: j['data'], link: j['link'] as String?);
    } on Object {
      return null; // missing or unreadable: an unconditional request
    }
  }

  @override
  Future<void> write(String key, EtagEntry entry) async {
    try {
      await dir.create(recursive: true);
      await _file(key)
          .writeAsString(jsonEncode({'key': key, 'etag': entry.etag, 'link': entry.link, 'data': entry.data}));
    } on Object {
      // Only an optimization.
    }
  }

  /// Deletes the oldest files beyond [maxEntries].
  Future<void> prune() async {
    try {
      if (!await dir.exists()) return;
      final files = await dir.list().where((e) => e is File).cast<File>().toList();
      if (files.length <= maxEntries) return;
      final stamped = [for (final f in files) (f, await f.lastModified())]..sort((a, b) => a.$2.compareTo(b.$2));
      for (final (f, _) in stamped.take(files.length - maxEntries)) {
        await f.delete();
      }
    } on Object {
      // Only an optimization.
    }
  }

  Future<void> clear() async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on Object {
      // Nothing to clear.
    }
  }
}
