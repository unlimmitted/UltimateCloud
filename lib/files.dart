import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:ultimate_cloud/video_player.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

class FilesScreen extends StatefulWidget {
  final String? currentPath;

  const FilesScreen({super.key, this.currentPath});

  @override
  State<FilesScreen> createState() => FilesScreenState();
}

class FilesScreenState extends State<FilesScreen> {
  List<dynamic> _files = [];
  bool _isLoading = false;

  Future<void> _fetchFiles() async {
    setState(() => _isLoading = true);
    final encodedPath = Uri.encodeComponent(widget.currentPath ?? '');
    final url = Uri.parse("https://ulcloud.ru/api/v1/storage/files?path=$encodedPath");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decoded);
        setState(() {
          _files = data;
          _files.sort((a, b) {
            final aIsFolder = a['type'] == 'directory';
            final bIsFolder = b['type'] == 'directory';
            if (aIsFolder && !bIsFolder) return -1;
            if (!aIsFolder && bIsFolder) return 1;
            return a['name'].toLowerCase().compareTo(b['name'].toLowerCase());
          });
        });
      } else {
        print("Ошибка загрузки: ${response.statusCode}");
      }
    } catch (e) {
      print("Ошибка: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> uploadFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;
    final uri = Uri.parse("https://ulcloud.ru/api/v1/storage/upload");
    final request = http.MultipartRequest('POST', uri)
      ..fields['path'] = widget.currentPath ?? ''
      ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: fileName));
    final response = await request.send();
    if (response.statusCode == 200) {
      print('Файл успешно загружен');
      await _fetchFiles();
    } else {
      print('Ошибка при загрузке: ${response.statusCode}');
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
      final uri = Uri.parse("https://ulcloud.ru/api/v1/storage/create-folder");
      final response = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'path': widget.currentPath ?? '',
            'name': result.trim(),
          }));
      if (response.statusCode == 201) {
        await _fetchFiles();
      } else {
        print('Ошибка при создании папки: ${response.statusCode}');
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
    final displayPath = currentPath.isEmpty ? "Файлы на сервере" : currentPath;
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchFiles,
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  final name = file['name']?.toString() ?? 'Без имени';
                  final isFolder = file['type'] == 'directory';
                  final size = int.tryParse(file['size'].toString()) ?? 0;
                  final progress = int.tryParse(file['progress'].toString()) ?? 0;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      leading: Icon(isFolder ? Icons.folder : (progress == 100 ? Icons.insert_drive_file : Icons.cloud_download)),
                      title: Text(name),
                      subtitle: !isFolder && progress < 100 ? Text('Загрузка: $progress%') : null,
                      onTap: () {
                        if (isFolder) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FilesScreen(
                                currentPath: "${widget.currentPath ?? ""}/$name".replaceAll('//', '/'),
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoScreen(
                                  filename: widget.currentPath != null ? '${currentPath.replaceAll("/", "")}/$name' : name),
                            ),
                          );
                        }
                      },
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: SpeedDial(
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
