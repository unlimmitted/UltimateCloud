import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player_16kb/flutter_vlc_player.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

class VideoScreen extends StatelessWidget {
  final String filename;

  const VideoScreen({
    super.key,
    required this.filename,
  });

  String _buildStreamUrl() {
    final pathSegments = filename
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList();

    return Uri(
      scheme: 'https',
      host: 'ulcloud.ru',
      pathSegments: [
        'api',
        'v1',
        'storage',
        'stream',
        ...pathSegments,
      ],
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final streamUrl = _buildStreamUrl();

    if (Platform.isWindows) {
      return _WindowsMediaKitPlayer(streamUrl: streamUrl);
    }

    return _MobileVlcPlayer(streamUrl: streamUrl);
  }
}

class _WindowsMediaKitPlayer extends StatefulWidget {
  final String streamUrl;

  const _WindowsMediaKitPlayer({
    required this.streamUrl,
  });

  @override
  State<_WindowsMediaKitPlayer> createState() => _WindowsMediaKitPlayerState();
}

class _WindowsMediaKitPlayerState extends State<_WindowsMediaKitPlayer> {
  late final media_kit.Player _player;
  late final media_kit_video.VideoController _videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  Timer? _hideControlsTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _controlsVisible = true;
  String? _error;

  @override
  void initState() {
    super.initState();

    _player = media_kit.Player();
    _videoController = media_kit_video.VideoController(_player);

    _subscriptions.addAll([
      _player.stream.position.listen((value) {
        if (!mounted) return;
        setState(() => _position = value);
      }),
      _player.stream.duration.listen((value) {
        if (!mounted) return;
        setState(() => _duration = value);
      }),
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
      }),
      _player.stream.buffering.listen((value) {
        if (!mounted) return;
        setState(() => _buffering = value);
      }),
      _player.stream.error.listen((value) {
        if (!mounted || value.trim().isEmpty) return;
        setState(() => _error = value);
      }),
      _player.stream.tracks.listen((_) {
        if (!mounted) return;
        setState(() {});
      }),
      _player.stream.track.listen((_) {
        if (!mounted) return;
        setState(() {});
      }),
    ]);

    _startHideControlsTimer();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final uri = Uri.parse(widget.streamUrl);

      // Короткая проверка сразу показывает реальный HTTP-код вместо
      // неинформативного "Failed to open".
      final probe = await http.get(
        uri,
        headers: const {
          'Range': 'bytes=0-1',
          'Accept': '*/*',
          'User-Agent': 'UltimateCloud/1.0',
        },
      ).timeout(const Duration(seconds: 20));

      if (probe.statusCode != 200 && probe.statusCode != 206) {
        throw Exception(
          'Сервер вернул HTTP ${probe.statusCode}: '
          '${probe.body.length > 200 ? probe.body.substring(0, 200) : probe.body}',
        );
      }

      await _player.open(
        media_kit.Media(
          widget.streamUrl,
          httpHeaders: const {
            'Accept': '*/*',
            'User-Agent': 'UltimateCloud/1.0',
          },
        ),
        play: true,
      );
    } catch (error, stackTrace) {
      debugPrint('media_kit open error: $error');
      debugPrint('URL: ${widget.streamUrl}');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _buffering = false;
        _error = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();

    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }

    unawaited(_player.dispose());
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;

    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }

    _startHideControlsTimer();
  }

  void _toggleControls() {
    if (!mounted) return;

    setState(() => _controlsVisible = !_controlsVisible);

    if (_controlsVisible) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _togglePlayPause() async {
    _showControls();
    await _player.playOrPause();
  }

  Future<void> _rewind10() async {
    _showControls();

    final target = _position - const Duration(seconds: 10);
    await _player.seek(target.isNegative ? Duration.zero : target);
  }

  Future<void> _forward10() async {
    _showControls();

    var target = _position + const Duration(seconds: 10);
    if (_duration > Duration.zero && target > _duration) {
      target = _duration;
    }

    await _player.seek(target);
  }

  Future<void> _seek(double milliseconds) async {
    _showControls();
    await _player.seek(Duration(milliseconds: milliseconds.round()));
  }

  String _audioTrackLabel(media_kit.AudioTrack track, int index) {
    if (track.id == 'auto') return 'Автоматически';

    final title = track.title?.trim();
    final language = track.language?.trim();

    if (title != null && title.isNotEmpty) {
      return language == null || language.isEmpty
          ? title
          : '$title ($language)';
    }

    if (language != null && language.isNotEmpty) {
      return language;
    }

    return 'Аудиодорожка ${index + 1}';
  }

  String _subtitleTrackLabel(media_kit.SubtitleTrack track, int index) {
    if (track.id == 'no') return 'Без субтитров';
    if (track.id == 'auto') return 'Автоматически';

    final title = track.title?.trim();
    final language = track.language?.trim();

    if (title != null && title.isNotEmpty) {
      return language == null || language.isEmpty
          ? title
          : '$title ($language)';
    }

    if (language != null && language.isNotEmpty) {
      return language;
    }

    return 'Субтитры ${index + 1}';
  }

  Future<void> _selectAudioTrack() async {
    _showControls();

    final tracks =
        _player.state.tracks.audio.where((track) => track.id != 'no').toList();
    final selectedId = _player.state.track.audio.id;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Выбор аудиодорожки'),
        children: [
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Аудиодорожки не найдены'),
            ),
          for (var index = 0; index < tracks.length; index++)
            RadioListTile<String>(
              value: tracks[index].id,
              groupValue: selectedId,
              title: Text(_audioTrackLabel(tracks[index], index)),
              onChanged: (_) async {
                Navigator.of(dialogContext).pop();
                await _player.setAudioTrack(tracks[index]);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _selectSubtitleTrack() async {
    _showControls();

    final tracks = _player.state.tracks.subtitle
        .where((track) => track.id != 'auto')
        .toList();

    if (!tracks.any((track) => track.id == 'no')) {
      tracks.insert(0, media_kit.SubtitleTrack.no());
    }

    final selectedId = _player.state.track.subtitle.id;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Выбор субтитров'),
        children: [
          for (var index = 0; index < tracks.length; index++)
            RadioListTile<String>(
              value: tracks[index].id,
              groupValue: selectedId,
              title: Text(_subtitleTrackLabel(tracks[index], index)),
              onChanged: (_) async {
                Navigator.of(dialogContext).pop();
                await _player.setSubtitleTrack(tracks[index]);
              },
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }

    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Map<ShortcutActivator, Intent> get _shortcuts => const {
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.mediaPlayPause): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft):
            DirectionalFocusIntent(TraversalDirection.left),
        SingleActivator(LogicalKeyboardKey.arrowRight):
            DirectionalFocusIntent(TraversalDirection.right),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
      };

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(
      _duration.inMilliseconds.toDouble(),
      1.0,
    );
    final current =
        _position.inMilliseconds.toDouble().clamp(0.0, maximum).toDouble();
    final remaining =
        _duration > _position ? _duration - _position : Duration.zero;

    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_togglePlayPause());
              return null;
            },
          ),
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              if (intent.direction == TraversalDirection.left) {
                unawaited(_rewind10());
              } else if (intent.direction == TraversalDirection.right) {
                unawaited(_forward10());
              }

              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: MouseRegion(
              onHover: (_) => _showControls(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: media_kit_video.Video(
                        controller: _videoController,
                        controls: media_kit_video.NoVideoControls,
                        fit: BoxFit.contain,
                        fill: Colors.black,
                      ),
                    ),
                    if (_buffering && _error == null)
                      const Center(
                        child: CircularProgressIndicator(),
                      ),
                    if (_controlsVisible) ...[
                      Positioned(
                        top: 30,
                        left: 10,
                        right: 10,
                        child: SafeArea(
                          child: Row(
                            children: [
                              IconButton(
                                iconSize: 36,
                                tooltip: 'Назад',
                                icon: const Icon(
                                  Icons.arrow_back,
                                  color: Colors.white,
                                ),
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                              const Spacer(),
                              IconButton(
                                iconSize: 36,
                                tooltip: 'Субтитры',
                                icon: const Icon(
                                  Icons.subtitles,
                                  color: Colors.white,
                                ),
                                onPressed: _selectSubtitleTrack,
                              ),
                              IconButton(
                                iconSize: 36,
                                tooltip: 'Аудиодорожка',
                                icon: const Icon(
                                  Icons.audiotrack,
                                  color: Colors.white,
                                ),
                                onPressed: _selectAudioTrack,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          color: Colors.black.withOpacity(0.55),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    iconSize: 48,
                                    tooltip: 'Назад на 10 секунд',
                                    icon: const Icon(
                                      Icons.replay_10,
                                      color: Colors.white,
                                    ),
                                    onPressed: _rewind10,
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    iconSize: 64,
                                    tooltip:
                                        _playing ? 'Пауза' : 'Воспроизвести',
                                    icon: Icon(
                                      _playing
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                                      color: Colors.white,
                                    ),
                                    onPressed: _togglePlayPause,
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    iconSize: 48,
                                    tooltip: 'Вперёд на 10 секунд',
                                    icon: const Icon(
                                      Icons.forward_10,
                                      color: Colors.white,
                                    ),
                                    onPressed: _forward10,
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    '-${_formatDuration(remaining)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: current,
                                max: maximum,
                                onChanged: _seek,
                                activeColor: Colors.red,
                                inactiveColor: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_error != null)
                      Center(
                        child: Card(
                          margin: const EdgeInsets.all(32),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 700),
                              child: SelectableText(
                                'Не удалось открыть видео:\n'
                                '$_error\n\n'
                                '${widget.streamUrl}',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileVlcPlayer extends StatefulWidget {
  final String streamUrl;

  const _MobileVlcPlayer({
    required this.streamUrl,
  });

  @override
  State<_MobileVlcPlayer> createState() => _MobileVlcPlayerState();
}

class _MobileVlcPlayerState extends State<_MobileVlcPlayer> {
  late final VlcPlayerController _controller;

  bool _controlsVisible = true;
  double _currentPosition = 0;
  double _videoDuration = 0;

  Timer? _progressTimer;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();

    _controller = VlcPlayerController.network(
      widget.streamUrl,
      hwAcc: HwAcc.disabled,
      autoPlay: true,
      options: VlcPlayerOptions(
        advanced: VlcAdvancedOptions([
          '--network-caching=5000',
          '--file-caching=5000',
          '--live-caching=5000',
          '--http-reconnect',
        ]),
        extras: [
          '--avcodec-hw=none',
          '--drop-late-frames',
          '--skip-frames',
        ],
      ),
    );

    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) async {
        if (!mounted || !_controller.value.isInitialized) return;

        try {
          final duration = await _controller.getDuration();
          final position = await _controller.getPosition();

          if (!mounted) return;

          setState(() {
            _videoDuration = duration.inMilliseconds.toDouble();
            _currentPosition = position.inMilliseconds.toDouble();
          });
        } catch (error) {
          debugPrint('VLC progress update error: $error');
        }
      },
    );

    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();

    try {
      if (_controller.value.isInitialized) {
        _controller.dispose();
      }
    } catch (error) {
      debugPrint('VLC dispose error: $error');
    }

    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _startHideControlsTimer();
  }

  void _toggleControls() {
    if (!mounted) return;

    setState(() => _controlsVisible = !_controlsVisible);

    if (_controlsVisible) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_controller.value.isInitialized) return;

    if (_controller.value.isPlaying) {
      await _controller.pause();
    } else {
      await _controller.play();
    }

    if (mounted) setState(() {});
  }

  Future<void> _rewind10() async {
    if (!_controller.value.isInitialized) return;

    final position = await _controller.getPosition();
    final target = math.max(0, position.inMilliseconds - 10000);

    await _controller.setTime(target);

    if (mounted) {
      setState(() => _currentPosition = target.toDouble());
    }
  }

  Future<void> _forward10() async {
    if (!_controller.value.isInitialized) return;

    final position = await _controller.getPosition();
    final duration = await _controller.getDuration();

    final target = math.min(
      duration.inMilliseconds,
      position.inMilliseconds + 10000,
    );

    await _controller.setTime(target);

    if (mounted) {
      setState(() => _currentPosition = target.toDouble());
    }
  }

  Future<void> _seek(double value) async {
    if (!_controller.value.isInitialized) return;

    await _controller.setTime(value.round());

    if (mounted) {
      setState(() => _currentPosition = value);
    }
  }

  Future<void> _selectSubtitleTrack() async {
    if (!_controller.value.isInitialized) return;

    final tracks = await _controller.getSpuTracks();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Выбор субтитров'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _controller.setSpuTrack(-1);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Без субтитров'),
          ),
          ...tracks.entries.map(
            (entry) => SimpleDialogOption(
              onPressed: () {
                _controller.setSpuTrack(entry.key);
                Navigator.of(dialogContext).pop();
              },
              child: Text(entry.value),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectAudioTrack() async {
    if (!_controller.value.isInitialized) return;

    final tracks = await _controller.getAudioTracks();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Выбор аудиодорожки'),
        children: tracks.entries
            .map(
              (entry) => SimpleDialogOption(
                onPressed: () {
                  _controller.setAudioTrack(entry.key);
                  Navigator.of(dialogContext).pop();
                },
                child: Text(entry.value),
              ),
            )
            .toList(),
      ),
    );
  }

  String _formatDuration(Duration value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:'
          '${twoDigits(seconds)}';
    }

    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(_videoDuration, 1.0);
    final current = _currentPosition.clamp(0.0, maximum).toDouble();
    final remaining = math.max(
      0,
      (_videoDuration - _currentPosition).round(),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          children: [
            Positioned.fill(
              child: VlcPlayer(
                controller: _controller,
                aspectRatio: 16 / 9,
                virtualDisplay: true,
                placeholder: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
            if (_controlsVisible) ...[
              Positioned(
                top: 30,
                left: 10,
                right: 10,
                child: SafeArea(
                  child: Row(
                    children: [
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const Spacer(),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.subtitles,
                          color: Colors.white,
                        ),
                        onPressed: _selectSubtitleTrack,
                      ),
                      IconButton(
                        iconSize: 36,
                        icon: const Icon(
                          Icons.audiotrack,
                          color: Colors.white,
                        ),
                        onPressed: _selectAudioTrack,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  color: Colors.black.withOpacity(0.55),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 48,
                            icon: const Icon(
                              Icons.replay_10,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              _showControls();
                              unawaited(_rewind10());
                            },
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            iconSize: 64,
                            icon: Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              _showControls();
                              unawaited(_togglePlayPause());
                            },
                          ),
                          const SizedBox(width: 24),
                          IconButton(
                            iconSize: 48,
                            icon: const Icon(
                              Icons.forward_10,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              _showControls();
                              unawaited(_forward10());
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                              Duration(
                                milliseconds: _currentPosition.round(),
                              ),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '-${_formatDuration(Duration(milliseconds: remaining))}',
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: current,
                        max: maximum,
                        onChanged: _seek,
                        activeColor: Colors.red,
                        inactiveColor: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
