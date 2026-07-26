import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:http/http.dart' as http;
import 'package:ultimate_cloud/video_player.dart';

import 'network/api_client.dart';

class FilesScreen extends StatefulWidget {
  final String? currentPath;

  const FilesScreen({super.key, this.currentPath});

  @override
  State<FilesScreen> createState() => FilesScreenState();
}

class FilesScreenState extends State<FilesScreen> {
  static const int _chunkSize = 5 * 1024 * 1024;

  List<dynamic> _files = [];
  Map<String, Map<String, dynamic>> _torrentMetadataByPath = {};
  bool _isLoading = false;
  bool _isUploading = false;
  int _uploadProgress = 0;

  bool get _isTvos => Platform.operatingSystem == 'tvos';

  String _joinServerPath(String basePath, String name) {
    final cleanBase = basePath.replaceAll(RegExp(r'^/+|/+$'), '');
    final cleanName = name.replaceAll(RegExp(r'^/+'), '');
    if (cleanBase.isEmpty) return cleanName;
    return '$cleanBase/$cleanName';
  }

  String _normalizeServerPath(String path) {
    return path
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'^/+|/+$'), '')
        .toLowerCase();
  }

  String _basename(String path) {
    final normalized = _normalizeServerPath(path);
    final separatorIndex = normalized.lastIndexOf('/');
    return separatorIndex >= 0 ? normalized.substring(separatorIndex + 1) : normalized;
  }

  Map<String, dynamic>? _findTorrentMetadata(String fullPath) {
    final normalizedPath = _normalizeServerPath(fullPath);
    final exactMatch = _torrentMetadataByPath[normalizedPath];
    if (exactMatch != null) return exactMatch;

    // Внутри папки торрента применяем метаданные корневой папки ко всем
    // вложенным файлам. Выбираем самый длинный подходящий путь.
    MapEntry<String, Map<String, dynamic>>? bestPrefixMatch;
    for (final entry in _torrentMetadataByPath.entries) {
      if (!normalizedPath.startsWith('${entry.key}/')) continue;
      if (bestPrefixMatch == null || entry.key.length > bestPrefixMatch.key.length) {
        bestPrefixMatch = entry;
      }
    }
    if (bestPrefixMatch != null) return bestPrefixMatch.value;

    // Fallback нужен, если storage endpoint возвращает путь относительно другой
    // корневой папки. Используем имя только при единственном совпадении.
    final fileName = _basename(normalizedPath);
    final matches = _torrentMetadataByPath.entries
        .where((entry) => _basename(entry.key) == fileName)
        .map((entry) => entry.value)
        .toList();

    return matches.length == 1 ? matches.single : null;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchTorrentMetadata() async {
    final uri = ApiClient.uri('/api/v1/torrent/downloaded-files');
    final response = await ApiClient.get(uri);

    if (response.statusCode != 200) {
      debugPrint('Ошибка загрузки метаданных торрентов: ${response.statusCode}');
      return {};
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) return {};

    final result = <String, Map<String, dynamic>>{};
    for (final item in decoded) {
      if (item is! Map) continue;

      final metadata = Map<String, dynamic>.from(item);
      final path = metadata['path']?.toString();
      final rootPath = metadata['rootPath']?.toString();

      if (path != null && path.trim().isNotEmpty) {
        result[_normalizeServerPath(path)] = metadata;
      }

      // В корневом списке Transmission-торрент обычно отображается папкой,
      // тогда как files[] содержит пути до вложенных видеофайлов.
      if (rootPath != null && rootPath.trim().isNotEmpty) {
        result[_normalizeServerPath(rootPath)] = metadata;
      }
    }

    return result;
  }

  Future<void> _fetchFiles() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }

    final url = ApiClient.uri(
      '/api/v1/storage/files',
      {'path': widget.currentPath ?? ''},
    );

    try {
      final responses = await Future.wait([
        ApiClient.get(url),
        _fetchTorrentMetadata(),
      ]);

      final filesResponse = responses[0] as http.Response;
      final torrentMetadata = responses[1] as Map<String, Map<String, dynamic>>;

      if (filesResponse.statusCode == 200) {
        final decoded = utf8.decode(filesResponse.bodyBytes);
        final data = jsonDecode(decoded);

        if (!mounted) return;

        setState(() {
          _files = data is List ? data : [];
          _torrentMetadataByPath = torrentMetadata;
          debugPrint('Метаданные скачанных торрентов: ${torrentMetadata.length} путей');
          _files.sort((a, b) {
            final aIsFolder = a['type'] == 'directory';
            final bIsFolder = b['type'] == 'directory';
            if (aIsFolder && !bIsFolder) return -1;
            if (!aIsFolder && bIsFolder) return 1;
            return a['name'].toString().toLowerCase().compareTo(
                  b['name'].toString().toLowerCase(),
                );
          });
        });
      } else if (filesResponse.statusCode == 401) {
        debugPrint('Не авторизован');
      } else {
        debugPrint('Ошибка загрузки: ${filesResponse.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('Ошибка загрузки файлов: $e');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildFileLeading({
    required bool isFolder,
    required int progress,
    required String? posterUrl,
  }) {
    if (posterUrl == null || posterUrl.trim().isEmpty) {
      return Icon(
        isFolder
            ? Icons.folder
            : (progress == 100 ? Icons.insert_drive_file : Icons.cloud_download),
      );
    }

    return SizedBox(
      width: 56,
      height: 78,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.network(
          posterUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            isFolder
                ? Icons.folder
                : (progress == 100 ? Icons.insert_drive_file : Icons.cloud_download),
          ),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget? _buildSubtitle({
    required bool isFolder,
    required int progress,
    required Map<String, dynamic>? metadata,
  }) {
    final lines = <String>[];
    final movieTitle = metadata?['movieTitle']?.toString().trim();

    if (movieTitle != null && movieTitle.isNotEmpty) {
      lines.add(movieTitle);
    }

    if (!isFolder && progress < 100) {
      lines.add('Загрузка: $progress%');
    }

    return lines.isEmpty ? null : Text(lines.join('\n'));
  }

  Future<void> uploadFile() async {
    if (_isTvos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Загрузка файлов с Apple TV не поддерживается')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;

    await uploadFileInChunks(
      file: file,
      fileName: fileName,
      path: widget.currentPath ?? '',
    );

    await _fetchFiles();
  }

  Future<void> uploadFileInChunks({
    required File file,
    required String fileName,
    required String path,
  }) async {
    final fileLength = await file.length();
    final totalChunks = (fileLength / _chunkSize).ceil();
    final uploadId = '${DateTime.now().millisecondsSinceEpoch}_${fileName.hashCode}';
    final raf = await file.open();

    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
        final start = chunkIndex * _chunkSize;
        final end = (start + _chunkSize > fileLength) ? fileLength : start + _chunkSize;

        await raf.setPosition(start);
        final bytes = await raf.read(end - start);

        final uri = ApiClient.uri('/api/v1/storage/upload-chunk');

        final request = http.MultipartRequest('POST', uri)
          ..fields['uploadId'] = uploadId
          ..fields['fileName'] = fileName
          ..fields['chunkIndex'] = chunkIndex.toString()
          ..fields['totalChunks'] = totalChunks.toString()
          ..fields['path'] = path
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: '$chunkIndex.part',
            ),
          );

        final cookie = await ApiClient.cookie;
        if (cookie != null && cookie.isNotEmpty) {
          request.headers['Cookie'] = cookie;
        }

        final response = await request.send();

        if (response.statusCode != 200) {
          throw Exception('Chunk upload failed: ${response.statusCode}');
        }

        if (!mounted) return;

        setState(() {
          _uploadProgress = (((chunkIndex + 1) / totalChunks) * 100).round();
        });
      }
    } finally {
      await raf.close();

      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> showCreateFolderDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Создать папку'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Имя папки'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final uri = ApiClient.uri('/api/v1/storage/create-folder');
      final response = await ApiClient.post(
        uri,
        jsonBody: true,
        body: {
          'path': widget.currentPath ?? '',
          'name': result.trim(),
        },
      );

      if (response.statusCode == 201) {
        await _fetchFiles();
      } else {
        debugPrint('Ошибка при создании папки: ${response.statusCode}');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = widget.currentPath ?? '';
    final displayPath = currentPath.isEmpty ? 'Файлы на сервере' : currentPath;

    return Scaffold(
      appBar: AppBar(
        title: Text(displayPath),
        leading: widget.currentPath != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _fetchFiles,
                  child: ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      final name = file['name']?.toString() ?? 'Без имени';
                      final isFolder = file['type'] == 'directory';
                      final progress = int.tryParse(file['progress'].toString()) ?? 0;
                      final fullPath = _joinServerPath(currentPath, name);
                      final metadata = _findTorrentMetadata(fullPath);
                      final posterUrl = metadata?['posterUrl']?.toString();

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          minLeadingWidth: 56,
                          leading: _buildFileLeading(
                            isFolder: isFolder,
                            progress: progress,
                            posterUrl: posterUrl,
                          ),
                          title: Text(name),
                          subtitle: _buildSubtitle(
                            isFolder: isFolder,
                            progress: progress,
                            metadata: metadata,
                          ),
                          onTap: () {
                            if (isFolder) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FilesScreen(currentPath: fullPath),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => VideoScreen(filename: fullPath),
                                ),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
          if (_isUploading)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Загрузка файла: $_uploadProgress%'),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _uploadProgress / 100),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _isTvos
          ? null
          : SpeedDial(
              animatedIcon: AnimatedIcons.menu_close,
              backgroundColor: Colors.grey[300],
              overlayOpacity: 0.1,
              children: [
                SpeedDialChild(
                  child: const Icon(Icons.cloud_upload),
                  label: 'Загрузить файл',
                  onTap: uploadFile,
                ),
                SpeedDialChild(
                  child: const Icon(Icons.create_new_folder),
                  label: 'Создать папку',
                  onTap: () => showCreateFolderDialog(context),
                ),
              ],
            ),
    );
  }
}
