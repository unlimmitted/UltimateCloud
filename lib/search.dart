import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

class SearchContainer extends StatefulWidget {
  const SearchContainer({super.key});

  @override
  _SearchContainerState createState() => _SearchContainerState();
}

class _SearchContainerState extends State<SearchContainer> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _results = [];
  Timer? _debounce;
  bool _isLoading = false;

  Future<void> _sendQuery(String text) async {
    if (text.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final url = Uri.parse("https://ulcloud.ru/api/v1/torrent/search-by-kinopoisk?query=$text");
    try {
      final response = await http.get(url).timeout(const Duration(minutes: 5));
      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decoded);
        setState(() {
          _results = data as List<dynamic>? ?? [];
          _isLoading = false;
        });
      } else {
        print("Ошибка: ${response.statusCode}");
        setState(() {
          _results = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Ошибка при отправке запроса: $e");
      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  void _onTextChanged(String text) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();

    setState(() {
      _isLoading = true;
    });

    _debounce = Timer(const Duration(milliseconds: 1500), () {
      _sendQuery(text);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Поиск по Кинопоиску',
              ),
              onChanged: _onTextChanged,
            ),
            // const SizedBox(height: 20),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? const Center(child: Text('Нет результатов'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final result = _results[index];
                            final title = result['name'] ?? result['alternativeName'] ?? 'Без названия';
                            final posterUrl = result['poster']?['previewUrl'];
                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetailScreen(
                                      item: result,
                                      query: '',
                                    ),
                                  ),
                                );
                              },
                              child: Card(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                elevation: 3,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (posterUrl != null)
                                      SizedBox(
                                        width: MediaQuery.of(context).size.width / 4,
                                        child: AspectRatio(
                                          aspectRatio: 2 / 3,
                                          child: ClipRRect(
                                            borderRadius: const BorderRadius.only(
                                              topLeft: Radius.circular(8.0),
                                              bottomLeft: Radius.circular(8.0),
                                            ),
                                            child: Image.network(
                                              posterUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) =>
                                                  const Icon(Icons.broken_image_outlined),
                                            ),
                                          ),
                                        ),
                                      ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                            ),
                                            if (result['alternativeName'] != null &&
                                                result['alternativeName'].toString().isNotEmpty)
                                              Text(
                                                result['alternativeName'],
                                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                                              ),
                                            if (result['year'] != null)
                                              Text(
                                                result['year'].toString(),
                                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                                              ),
                                            if (result['movieLength'] != null && result['movieLength'] > 0)
                                              Text(
                                                "${result['movieLength']} мин",
                                                style: const TextStyle(fontSize: 14, color: Colors.grey),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  final dynamic item;

  const DetailScreen({super.key, required this.item, required String query});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  List<dynamic> _rutrackerResults = [];
  bool _isLoadingRutracker = true;
  String? _downloadingTorrentHash;

  @override
  void initState() {
    super.initState();
    _fetchRutrackerResults();
  }

  String _formatSize(double sizeMb) {
    final sizeGb = sizeMb / 1024;
    return "${sizeGb.toStringAsFixed(2)} ГБ";
  }

  String _getResolution(Map<String, dynamic>? res) {
    if (res == null || res['height'] == null || res['width'] == null) return "Неизвестно";
    return "${res['height']}x${res['width']}";
  }

  Future<void> _fetchRutrackerResults() async {
    final name = "${widget.item['name']} ${widget.item['alternativeName']}";
    final query = widget.item['isSeries'] ? name : "$name ${widget.item['year']}";
    if (query.isEmpty) {
      return;
    }
    final url = Uri.parse("https://ulcloud.ru/api/v1/torrent/search-by-rutracker?query=$query");
    try {
      final response = await http.get(url).timeout(const Duration(minutes: 5));
      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decoded);
        setState(() {
          _rutrackerResults = data as List<dynamic>? ?? [];
          _isLoadingRutracker = false;
        });
      } else {
        print("Ошибка RuTracker: ${response.statusCode}");
        setState(() {
          _isLoadingRutracker = false;
        });
      }
    } catch (e) {
      print("Ошибка запроса RuTracker: $e");
      setState(() {
        _isLoadingRutracker = false;
      });
    }
  }

  Future<void> _downloadMovie(Map<String, dynamic> torrent, String hash) async {
    setState(() {
      _downloadingTorrentHash = hash;
    });

    final url = Uri.parse("https://ulcloud.ru/api/v1/torrent/download-by-transmission");
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(torrent),
          )
          .timeout(const Duration(minutes: 5));
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Торрент добавлен на загрузку"),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Ошибка добавления"),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Ошибка добавления"),
      ));
      print("Ошибка Transmission: $e");
    }

    setState(() {
      _downloadingTorrentHash = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final poster = item['poster']?['url'] ?? '';
    final title = item['name'] ?? item['alternativeName'] ?? 'Без названия';
    final year = item['year']?.toString() ?? '';
    final description = item['description'] ?? 'Описание отсутствует';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: MediaQuery.of(context).size.height * 0.55,
            flexibleSpace: FlexibleSpaceBar(
              background: poster.isNotEmpty
                  ? Image.network(
                      poster,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(child: Icon(Icons.image_not_supported, size: 100)),
                    )
                  : const Center(child: Icon(Icons.image_not_supported, size: 100)),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  if (year.isNotEmpty)
                    Text("${item['isSeries'] ? 'Сериал\n' : ''}Год выпуска: $year",
                        style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 10),
                  Text(description),
                  const Divider(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Результаты с RuTracker:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Изменить запрос',
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) {
                              var name = widget.item['name'] ?? widget.item['alternativeName'] ?? '';
                              var query = widget.item['isSeries'] ? name : "$name ${widget.item['year']}";
                              final controller = TextEditingController(text: query);
                              return AlertDialog(
                                title: const Text("Редактировать запрос"),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(
                                    hintText: "Введите новый запрос",
                                  ),
                                  autofocus: true,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text("Отмена"),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      final updatedQuery = controller.text.trim();
                                      if (updatedQuery.isNotEmpty) {
                                        Navigator.of(context).pop();
                                        Navigator.of(context).pushReplacement(
                                          MaterialPageRoute(
                                            builder: (context) => DetailScreen(
                                              query: updatedQuery,
                                              item: {
                                                ...widget.item,
                                                'name': updatedQuery,
                                              },
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text("Обновить"),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingRutracker)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_rutrackerResults.isEmpty)
                    const Text("Ничего не найдено.")
                  else
                    ..._rutrackerResults.map((torrent) {
                      final seeds = torrent['seeds'] ?? 0;
                      final downloads =
                          torrent['downloads'] > 1000 ? "${torrent['downloads'] ~/ 1000}k" : torrent['downloads'] ?? 0;
                      final resolution = _getResolution(torrent['movieResolution']);
                      final sizeMb = (torrent['size'] ?? 0).toDouble();
                      final size = _formatSize(sizeMb);
                      final hash = torrent['hash'] ?? torrent['title'];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text("Скачан $downloads раз\nСиды: $seeds"),
                          subtitle: Text("Разрешение: $resolution\nРазмер: $size"),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.info_outline),
                                tooltip: "Название раздачи",
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text("Название раздачи"),
                                      content: SingleChildScrollView(
                                        child: Text(torrent["title"]),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context, rootNavigator: true).pop();
                                          },
                                          child: const Text("Закрыть"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              _downloadingTorrentHash == hash
                                  ? const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.download_outlined),
                                      tooltip: "Скачать",
                                      onPressed: () => _downloadMovie(torrent, hash),
                                    ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
