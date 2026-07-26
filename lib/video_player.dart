import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player_16kb/flutter_vlc_player.dart';

class VideoScreen extends StatefulWidget {
  final String filename;

  const VideoScreen({super.key, required this.filename});

  @override
  State<VideoScreen> createState() => _CustomVlcPlayerState();
}

class _CustomVlcPlayerState extends State<VideoScreen> {
  late final VlcPlayerController _controller;

  bool _controlsVisible = true;
  double _currentPosition = 0;
  double _videoDuration = 0;

  Timer? _progressTimer;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();

    final encodedUrl = Uri.encodeFull(
      'https://ulcloud.ru/api/v1/storage/stream/${widget.filename}',
    );

    _controller = VlcPlayerController.network(
      encodedUrl,
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

    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!mounted) return;
      if (!_controller.value.isInitialized) {
        return;
      }

      try {
        final duration = await _controller.getDuration();
        final position = await _controller.getPosition();

        if (!mounted) {
          return;
        }

        setState(() {
          _videoDuration = duration.inMilliseconds.toDouble();
          _currentPosition = position.inMilliseconds.toDouble();
        });
      } catch (e) {
        debugPrint('VLC progress update error: $e');
      }
    });

    _startHideControlsTimer();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideControlsTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _onUserInteraction() {
    if (!mounted) return;
    setState(() {
      _controlsVisible = true;
    });
    _startHideControlsTimer();
  }

  void _toggleControls() {
    if (!mounted) return;
    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_controlsVisible) {
      _startHideControlsTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  Future<void> _togglePlayPause() async {
    if (!_controller.value.isInitialized) return;

    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
      } else {
        await _controller.play();
      }

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      debugPrint('VLC play/pause error: $e');
    }
  }

  Future<void> _rewind10() async {
    if (!_controller.value.isInitialized) return;

    try {
      final position = await _controller.getPosition();
      final newTime = (position.inMilliseconds - 10000).clamp(0, 1 << 31);
      await _controller.setTime(newTime);

      if (!mounted) return;
      setState(() {
        _currentPosition = newTime.toDouble();
      });
    } catch (e) {
      debugPrint('VLC rewind error: $e');
    }
  }

  Future<void> _forward10() async {
    if (!_controller.value.isInitialized) return;

    try {
      final position = await _controller.getPosition();
      final duration = await _controller.getDuration();

      var newTime = position.inMilliseconds + 10000;
      if (duration.inMilliseconds > 0 && newTime > duration.inMilliseconds) {
        newTime = duration.inMilliseconds;
      }

      await _controller.setTime(newTime);

      if (!mounted) return;
      setState(() {
        _currentPosition = newTime.toDouble();
      });
    } catch (e) {
      debugPrint('VLC forward error: $e');
    }
  }

  Future<void> _onSliderChanged(double value) async {
    if (!_controller.value.isInitialized) return;

    try {
      await _controller.setTime(value.toInt());

      if (!mounted) return;
      setState(() {
        _currentPosition = value;
      });
    } catch (e) {
      debugPrint('VLC seek error: $e');
    }
  }

  double _getAspectRatio() {
    final size = _controller.value.size;
    if (size.width > 0 && size.height > 0) {
      return size.width / size.height;
    }
    return 16 / 9;
  }

  Future<void> _selectSubtitleTrack() async {
    if (!_controller.value.isInitialized) return;

    final subs = await _controller.getSpuTracks();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Выбор субтитров'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _controller.setSpuTrack(-1);
              Navigator.pop(context);
            },
            child: const Text('Без субтитров'),
          ),
          ...subs.entries.map((e) {
            return SimpleDialogOption(
              onPressed: () {
                _controller.setSpuTrack(e.key);
                Navigator.pop(context);
              },
              child: Text(e.value),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _selectAudioTrack() async {
    if (!_controller.value.isInitialized) return;

    final tracks = await _controller.getAudioTracks();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Выбор аудио дорожки'),
        children: tracks.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () {
              _controller.setAudioTrack(e.key);
              Navigator.pop(context);
            },
            child: Text(e.value),
          );
        }).toList(),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }

    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Map<ShortcutActivator, Intent> get _shortcuts => const {
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.mediaPlayPause): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.arrowLeft): DirectionalFocusIntent(TraversalDirection.left),
    SingleActivator(LogicalKeyboardKey.arrowRight): DirectionalFocusIntent(TraversalDirection.right),
    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up),
    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down),
    SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
  };

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _onUserInteraction();
              _togglePlayPause();
              return null;
            },
          ),
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              _onUserInteraction();

              if (intent.direction == TraversalDirection.left) {
                _rewind10();
              } else if (intent.direction == TraversalDirection.right) {
                _forward10();
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
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onUserInteraction,
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: _toggleControls,
                    child: SizedBox.expand(
                      child: VlcPlayer(
                        controller: _controller,
                        aspectRatio: _getAspectRatio(),
                        virtualDisplay: true,
                        placeholder: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                  ),
                  if (_controlsVisible) _buildTopControls(context),
                  if (_controlsVisible) _buildBottomControls(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopControls(BuildContext context) {
    return Positioned(
      top: 30,
      left: 10,
      right: 10,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.subtitles, color: Colors.white),
              onPressed: _selectSubtitleTrack,
            ),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.audiotrack, color: Colors.white),
              onPressed: _selectAudioTrack,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final remaining = (_videoDuration - _currentPosition).clamp(0, double.infinity).toInt();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: () {
                    _onUserInteraction();
                    _rewind10();
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 64,
                  icon: Icon(
                    _controller.value.isPlaying ? Icons.pause_circle : Icons.play_circle,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _onUserInteraction();
                    _togglePlayPause();
                  },
                ),
                const SizedBox(width: 24),
                IconButton(
                  iconSize: 48,
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: () {
                    _onUserInteraction();
                    _forward10();
                  },
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(Duration(milliseconds: _currentPosition.toInt())),
                  style: const TextStyle(color: Colors.white),
                ),
                Text(
                  '-${_formatDuration(Duration(milliseconds: remaining))}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            Slider(
              value: _currentPosition.clamp(0, _videoDuration > 0 ? _videoDuration : 1),
              max: _videoDuration > 0 ? _videoDuration : 1,
              onChanged: (value) {
                _onUserInteraction();
                _onSliderChanged(value);
              },
              activeColor: Colors.red,
              inactiveColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
