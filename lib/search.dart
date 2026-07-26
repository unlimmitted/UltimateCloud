import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'network/api_client.dart';

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
    final query = text.trim();

    if (query.isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final url = ApiClient.uri(
      '/api/v1/torrent/search-by-kinopoisk',
      {'query': query},
    );

    try {
      final response = await ApiClient.get(url).timeout(const Duration(minutes: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decoded);
        setState(() {
          _results = data as List<dynamic>? ?? [];
          _isLoading = false;
        });
      } else {
        debugPrint("Ошибка: ${response.statusCode}");
        setState(() {
          _results = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Ошибка при отправке запроса: $e");

      if (!mounted) return;

      setState(() {
        _results = [];
        _isLoading = false;
      });
    }
  }

  void _onTextChanged(String text) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();

    setState(() {
      _isLoading = text.trim().isNotEmpty;
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
                                      query: _buildRutrackerQueryFromKinopoiskItem(result),
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

  String _buildRutrackerQueryFromKinopoiskItem(dynamic item) {
    final name = item['name']?.toString().trim() ?? '';
    final alternativeName = item['alternativeName']?.toString().trim() ?? '';
    final year = item['year']?.toString().trim() ?? '';
    final isSeries = item['isSeries'] == true;

    final title = name.isNotEmpty ? name : alternativeName;

    if (isSeries) {
      return title;
    }

    return [title, year].where((part) => part.trim().isNotEmpty).join(' ').trim();
  }
}

class DetailScreen extends StatefulWidget {
  final dynamic item;
  final String query;

  const DetailScreen({
    super.key,
    required this.item,
    required this.query,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  static const int _pageSize = 50;

  final ScrollController _scrollController = ScrollController();

  List<dynamic> _rutrackerResults = [];
  bool _isLoadingRutracker = true;
  bool _isLoadingMoreRutracker = false;
  bool _hasMoreRutracker = true;
  int _currentPage = 0;

  String? _downloadingTorrentHash;
  late String _rutrackerQuery;

  @override
  void initState() {
    super.initState();
    _rutrackerQuery = _buildInitialRutrackerQuery();
    _scrollController.addListener(_onScroll);
    _fetchRutrackerResults(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingRutracker || _isLoadingMoreRutracker || !_hasMoreRutracker) return;

    final position = _scrollController.position;
    final isNearBottom = position.pixels >= position.maxScrollExtent - 500;

    if (isNearBottom) {
      _fetchRutrackerResults();
    }
  }

  String _buildInitialRutrackerQuery() {
    final passedQuery = widget.query.trim();
    if (passedQuery.isNotEmpty) {
      return passedQuery;
    }

    final name = widget.item['name']?.toString() ?? '';
    final alternativeName = widget.item['alternativeName']?.toString() ?? '';
    final year = widget.item['year']?.toString() ?? '';
    final isSeries = widget.item['isSeries'] == true;

    final title = [name, alternativeName].where((part) => part.trim().isNotEmpty).join(' ').trim();

    if (isSeries) {
      return title;
    }

    return [title, year].where((part) => part.trim().isNotEmpty).join(' ').trim();
  }

  String _formatSize(double sizeMb) {
    final sizeGb = sizeMb / 1024;
    return "${sizeGb.toStringAsFixed(2)} ГБ";
  }

  String _getResolution(Map<String, dynamic>? res) {
    if (res == null || res['height'] == null || res['width'] == null) return "Неизвестно";
    return "${res['height']}x${res['width']}";
  }

  Future<void> _fetchRutrackerResults({bool reset = false}) async {
    final query = _rutrackerQuery.trim();

    if (query.isEmpty) {
      setState(() {
        _rutrackerResults = [];
        _isLoadingRutracker = false;
        _isLoadingMoreRutracker = false;
        _hasMoreRutracker = false;
      });
      return;
    }

    if (reset) {
      setState(() {
        _currentPage = 0;
        _hasMoreRutracker = true;
        _isLoadingRutracker = true;
        _isLoadingMoreRutracker = false;
        _rutrackerResults = [];
      });
    } else {
      if (!_hasMoreRutracker || _isLoadingMoreRutracker) return;

      setState(() {
        _isLoadingMoreRutracker = true;
      });
    }

    final pageToLoad = reset ? 0 : _currentPage + 1;

    final url = ApiClient.uri(
      '/api/v1/torrent/search-by-rutracker',
      {
        'query': query,
        'page': pageToLoad.toString(),
        'size': _pageSize.toString(),
      },
    );

    try {
      final response = await ApiClient.get(url).timeout(const Duration(minutes: 5));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final data = jsonDecode(decoded);

        final List<dynamic> newItems;
        final bool hasNext;

        if (data is Map<String, dynamic>) {
          newItems = data['items'] as List<dynamic>? ?? [];
          hasNext = data['hasNext'] == true;
        } else if (data is List<dynamic>) {
          newItems = data;
          hasNext = false;
        } else {
          newItems = [];
          hasNext = false;
        }

        setState(() {
          if (reset) {
            _rutrackerResults = newItems;
          } else {
            _rutrackerResults.addAll(newItems);
          }

          _currentPage = pageToLoad;
          _hasMoreRutracker = hasNext;
          _isLoadingRutracker = false;
          _isLoadingMoreRutracker = false;
        });
      } else {
        debugPrint("Ошибка RuTracker: ${response.statusCode}");

        setState(() {
          _isLoadingRutracker = false;
          _isLoadingMoreRutracker = false;
          _hasMoreRutracker = false;
        });
      }
    } catch (e) {
      debugPrint("Ошибка запроса RuTracker: $e");

      if (!mounted) return;

      setState(() {
        _isLoadingRutracker = false;
        _isLoadingMoreRutracker = false;
        _hasMoreRutracker = false;
      });
    }
  }

  Future<void> _downloadMovie(Map<String, dynamic> torrent, String hash) async {
    setState(() {
      _downloadingTorrentHash = hash;
    });

    final item = Map<String, dynamic>.from(widget.item as Map);
    final kinopoiskId = item['id']?.toString();
    final movieTitle = (item['name'] ?? item['alternativeName'])?.toString();
    final poster = item['poster'];
    final posterUrl = poster is Map ? (poster['previewUrl'] ?? poster['url'])?.toString() : null;

    final queryParameters = <String, String>{};
    if (kinopoiskId != null && kinopoiskId.isNotEmpty) {
      queryParameters['kinopoiskUrl'] = 'https://www.kinopoisk.ru/film/$kinopoiskId/';
    }
    if (posterUrl != null && posterUrl.isNotEmpty) {
      queryParameters['posterUrl'] = posterUrl;
    }
    if (movieTitle != null && movieTitle.isNotEmpty) {
      queryParameters['movieTitle'] = movieTitle;
    }

    final url = ApiClient.uri(
      '/api/v1/torrent/download-by-transmission',
      queryParameters,
    );

    try {
      final response = await ApiClient.post(
        url,
        jsonBody: true,
        body: torrent,
      ).timeout(const Duration(minutes: 10));

      if (!mounted) return;

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
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Ошибка добавления"),
      ));
      debugPrint("Ошибка Transmission: $e");
    }

    if (!mounted) return;

    setState(() {
      _downloadingTorrentHash = null;
    });
  }

  Future<void> _showEditQueryDialog() async {
    final controller = TextEditingController(text: _rutrackerQuery);

    final updatedQuery = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Редактировать запрос"),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Введите новый запрос",
            ),
            autofocus: true,
            onSubmitted: (value) {
              final query = value.trim();
              if (query.isNotEmpty) {
                Navigator.of(context).pop(query);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Отмена"),
            ),
            ElevatedButton(
              onPressed: () {
                final query = controller.text.trim();
                if (query.isNotEmpty) {
                  Navigator.of(context).pop(query);
                }
              },
              child: const Text("Обновить"),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (updatedQuery == null || updatedQuery.isEmpty || updatedQuery == _rutrackerQuery) {
      return;
    }

    setState(() {
      _rutrackerQuery = updatedQuery;
    });

    await _fetchRutrackerResults(reset: true);
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
        controller: _scrollController,
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
              child: _buildContent(item, title, year, description),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(dynamic item, String title, String year, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        if (year.isNotEmpty)
          Text(
            "${item['isSeries'] ? 'Сериал\n' : ''}Год выпуска: $year",
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        const SizedBox(height: 10),
        Text(description),
        const Divider(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                "Результаты с RuTracker:\n$_rutrackerQuery",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Изменить запрос',
              onPressed: _showEditQueryDialog,
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
          ..._rutrackerResults.map(_buildTorrentCard),
        if (_isLoadingMoreRutracker)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_hasMoreRutracker && _rutrackerResults.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: OutlinedButton(
                onPressed: () => _fetchRutrackerResults(),
                child: const Text('Загрузить ещё'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTorrentCard(dynamic torrent) {
    final seeds = torrent['seeds'] ?? 0;
    final downloads = torrent['downloads'] > 1000 ? "${torrent['downloads'] ~/ 1000}k" : torrent['downloads'] ?? 0;
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
  }
}
