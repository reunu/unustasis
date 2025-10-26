import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

/// Service for caching scooter images from cloud URLs
class ImageCacheService {
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;
  ImageCacheService._internal();

  final log = Logger('ImageCacheService');
  Directory? _cacheDirectory;
  
  /// Initialize the cache directory
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = Directory('${appDir.path}/scooter_images');
      
      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }
      
      log.info('Image cache initialized at: ${_cacheDirectory!.path}');
    } catch (e, stack) {
      log.severe('Failed to initialize image cache', e, stack);
    }
  }
  
  /// Generate cache key from URL
  String _getCacheKey(String url) {
    // Simple hash function without crypto dependency
    return url.hashCode.abs().toString();
  }
  
  /// Get cached image file path
  String? _getCachedImagePath(String url) {
    if (_cacheDirectory == null) return null;
    
    final cacheKey = _getCacheKey(url);
    final extension = _getFileExtension(url);
    return '${_cacheDirectory!.path}/$cacheKey$extension';
  }
  
  /// Extract file extension from URL
  String _getFileExtension(String url) {
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return '.jpg';
    if (path.endsWith('.png')) return '.png';
    if (path.endsWith('.webp')) return '.webp';
    if (path.endsWith('.gif')) return '.gif';
    
    return '.jpg'; // Default to jpg
  }
  
  /// Check if image is cached
  Future<bool> isCached(String url) async {
    final cachedPath = _getCachedImagePath(url);
    if (cachedPath == null) return false;
    
    final file = File(cachedPath);
    return await file.exists();
  }
  
  /// Get cached image file
  Future<File?> getCachedImage(String url) async {
    final cachedPath = _getCachedImagePath(url);
    if (cachedPath == null) return null;
    
    final file = File(cachedPath);
    if (await file.exists()) {
      return file;
    }
    
    return null;
  }
  
  /// Download and cache image from URL
  Future<File?> downloadAndCache(String url) async {
    try {
      if (_cacheDirectory == null) {
        await initialize();
        if (_cacheDirectory == null) return null;
      }
      
      log.info('Downloading image: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Unustasis/1.0',
        },
      );
      
      if (response.statusCode != 200) {
        log.warning('Failed to download image: ${response.statusCode}');
        return null;
      }
      
      final cachedPath = _getCachedImagePath(url);
      if (cachedPath == null) return null;
      
      final file = File(cachedPath);
      await file.writeAsBytes(response.bodyBytes);
      
      log.info('Image cached: $cachedPath');
      return file;
      
    } catch (e, stack) {
      log.severe('Failed to download and cache image: $url', e, stack);
      return null;
    }
  }
  
  /// Get image - returns cached if available, downloads if not
  Future<File?> getImage(String url) async {
    // Check cache first
    final cached = await getCachedImage(url);
    if (cached != null) {
      return cached;
    }
    
    // Download and cache
    return await downloadAndCache(url);
  }
  
  /// Clear entire image cache
  Future<void> clearCache() async {
    try {
      if (_cacheDirectory != null && await _cacheDirectory!.exists()) {
        await _cacheDirectory!.delete(recursive: true);
        await _cacheDirectory!.create(recursive: true);
        log.info('Image cache cleared');
      }
    } catch (e, stack) {
      log.severe('Failed to clear image cache', e, stack);
    }
  }
  
  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    try {
      if (_cacheDirectory == null || !await _cacheDirectory!.exists()) {
        return 0;
      }
      
      int totalSize = 0;
      await for (final entity in _cacheDirectory!.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      
      return totalSize;
    } catch (e, stack) {
      log.severe('Failed to calculate cache size', e, stack);
      return 0;
    }
  }
  
  /// Clean up old cached images (older than specified days)
  Future<void> cleanupOldImages({int maxAgeInDays = 30}) async {
    try {
      if (_cacheDirectory == null || !await _cacheDirectory!.exists()) {
        return;
      }
      
      final cutoffDate = DateTime.now().subtract(Duration(days: maxAgeInDays));
      int deletedCount = 0;
      
      await for (final entity in _cacheDirectory!.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
            deletedCount++;
          }
        }
      }
      
      log.info('Cleaned up $deletedCount old cached images');
    } catch (e, stack) {
      log.severe('Failed to cleanup old images', e, stack);
    }
  }
}