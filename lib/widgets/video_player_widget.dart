import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'mobile_player_controls.dart';
import 'pc_player_controls.dart';
import 'video_player_surface.dart';
import '../models/subtitle_cue.dart';
import '../services/subtitle_service.dart';

/// 字幕显示模式
enum SubtitleDisplayMode {
  /// 关闭字幕
  off,

  /// 使用视频内嵌字幕轨
  embedded,

  /// 使用外部字幕文件
  external,
}

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerSurface surface;
  final String? url;
  final Map<String, String>? headers;
  final VoidCallback? onBackPressed;
  final Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final Function(bool isPipMode)? onPipModeChanged;
  final String? subtitleUrl;

  const VideoPlayerWidget({
    super.key,
    this.surface = VideoPlayerSurface.mobile,
    this.url,
    this.headers,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onNextEpisode,
    this.onVideoCompleted,
    this.onPause,
    this.isLastEpisode = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
    this.onWebFullscreenChanged,
    this.onExitFullScreen,
    this.live = false,
    this.onPipModeChanged,
    this.subtitleUrl,
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class VideoPlayerWidgetController {
  VideoPlayerWidgetController._(this._state);
  final _VideoPlayerWidgetState _state;

  Future<void> updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    await _state._updateDataSource(
      url,
      startAt: startAt,
      headers: headers,
    );
  }

  Future<void> seekTo(Duration position) async {
    await _state._player?.seek(position);
  }

  Duration? get currentPosition => _state._player?.state.position;

  Duration? get duration => _state._player?.state.duration;

  bool get isPlaying => _state._player?.state.playing ?? false;

  Future<void> pause() async {
    await _state._player?.pause();
  }

  Future<void> play() async {
    await _state._player?.play();
  }

  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  Future<void> setSpeed(double speed) async {
    await _state._setPlaybackSpeed(speed);
  }

  double get playbackSpeed => _state._playbackSpeed.value;

  Future<void> setVolume(double volume) async {
    await _state._player?.setVolume(volume);
  }

  double? get volume => _state._player?.state.volume;

  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }

  Future<void> dispose() async {
    await _state._externalDispose();
  }

  bool get isPipMode => _state._isPipMode;

  // ==================== 字幕控制 ====================

  /// 获取当前字幕显示模式
  SubtitleDisplayMode get subtitleMode => _state._subtitleMode;

  /// 字幕是否开启（非 off 模式）
  bool get isSubtitleEnabled => _state._subtitleMode != SubtitleDisplayMode.off;

  /// 获取内嵌字幕轨列表
  List<SubtitleTrack> get embeddedSubtitleTracks =>
      _state._embeddedSubtitleTracks;

  /// 获取当前选中的内嵌字幕轨
  SubtitleTrack? get currentSubtitleTrack =>
      _state._currentSubtitleTrack;

  /// 是否已加载外部字幕
  bool get hasExternalSubtitle => _state._externalCues.isNotEmpty;

  /// 切换字幕模式：off / embedded / external
  Future<void> setSubtitleMode(SubtitleDisplayMode mode) async {
    await _state._setSubtitleMode(mode);
  }

  /// 选择指定的内嵌字幕轨
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    await _state._setSubtitleTrack(track);
  }

  /// 从 URL 加载外部字幕（SRT / VTT）
  Future<bool> loadExternalSubtitle(String url) async {
    return await _state._loadExternalSubtitle(url);
  }

  /// 清除外部字幕
  void clearExternalSubtitle() {
    _state._clearExternalSubtitle();
  }
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _hasCompleted = false;
  bool _isLoadingVideo = false;
  String? _currentUrl;
  Map<String, String>? _currentHeaders;
  final List<VoidCallback> _progressListeners = [];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  final ValueNotifier<double> _playbackSpeed = ValueNotifier<double>(1.0);
  bool _playerDisposed = false;
  VoidCallback? _exitWebFullscreenCallback;
  final Pip _pip = Pip();
  bool _isPipMode = false;

  // ==================== 字幕状态 ====================
  SubtitleDisplayMode _subtitleMode = SubtitleDisplayMode.off;
  List<SubtitleCue> _externalCues = [];
  String _currentSubtitleText = '';
  List<SubtitleTrack> _embeddedSubtitleTracks = [];
  SubtitleTrack? _currentSubtitleTrack;
  StreamSubscription<Tracks>? _tracksSubscription;
  String? _loadedSubtitleUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    _setupPip();
    _registerPipObserver();
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));

    // 如果传入了字幕 URL，自动加载外部字幕
    if (widget.subtitleUrl != null && widget.subtitleUrl!.isNotEmpty) {
      _loadExternalSubtitle(widget.subtitleUrl!).then((success) {
        if (success && mounted) {
          _setSubtitleMode(SubtitleDisplayMode.external);
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headers != oldWidget.headers && widget.headers != null) {
      _currentHeaders = widget.headers;
    }
    if (widget.url != oldWidget.url && widget.url != null) {
      unawaited(_updateDataSource(widget.url!));
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _player = Player();
    _videoController = VideoController(_player!);
    _setupPlayerListeners();
    if (_currentUrl != null) {
      await _openCurrentMedia();
    }
    if (!mounted || _playerDisposed) return;
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }
    setState(() {
      _isLoadingVideo = true;
    });
    try {
      await _player!.open(
        Media(
          _currentUrl!,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      if (!mounted || _playerDisposed || _player == null) return;
      await _player!.setRate(_playbackSpeed.value);
      if (!mounted || _playerDisposed) return;
      setState(() {
        _hasCompleted = false;
        // _isLoadingVideo = false;
      });
      // widget.onReady?.call();
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open media $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _setupPlayerListeners() {
    if (_player == null) {
      return;
    }
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();
    _tracksSubscription?.cancel();

    _positionSubscription = _player!.stream.position.listen((position) {
      // 更新外部字幕文本
      if (_subtitleMode == SubtitleDisplayMode.external &&
          _externalCues.isNotEmpty) {
        final text = SubtitleService.findSubtitleText(_externalCues, position);
        if (text != _currentSubtitleText && mounted) {
          setState(() {
            _currentSubtitleText = text;
          });
        }
      }

      for (final listener in List<VoidCallback>.from(_progressListeners)) {
        try {
          listener();
        } catch (error) {
          debugPrint('VideoPlayerWidget: progress listener error $error');
        }
      }
    });

    // 监听音视频轨变化，获取可用的内嵌字幕轨
    _tracksSubscription = _player!.stream.tracks.listen((tracks) {
      if (!mounted) return;
      setState(() {
        _embeddedSubtitleTracks = tracks.subtitle;
      });
    });

    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (!mounted) return;
      if (!playing) {
        setState(() {
          _hasCompleted = false;
        });
        _pip.setup(const PipOptions(
          autoEnterEnabled: false,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      } else {
        _pip.setup(const PipOptions(
          autoEnterEnabled: true,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ));
      }
    });

    if (!widget.live) {
      _completedSubscription = _player!.stream.completed.listen((completed) {
        if (!mounted) return;
        if (completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onVideoCompleted?.call();
        }
      });
    }

    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (!mounted) return;
      if (duration != Duration.zero) {
        if (_isLoadingVideo) {
          setState(() {
            _isLoadingVideo = false;
          });
        }
        widget.onReady?.call();
      }
    });
  }

  Future<void> _updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    if (_playerDisposed) {
      return;
    }
    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    if (_player == null) {
      await _initializePlayer();
      return;
    }

    setState(() {
      _isLoadingVideo = true;
    });

    try {
      final currentSpeed = _player!.state.rate;
      await _player!.open(
        Media(
          url,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
        play: true,
      );
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);
      if (mounted) {
        setState(() {
          _hasCompleted = false;
          // _isLoadingVideo = false;
        });
      }
      // widget.onReady?.call();
    } catch (error) {
      debugPrint('VideoPlayerWidget: error while changing source $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    await _player?.setRate(speed);
  }

  // ==================== 字幕控制方法 ====================

  /// 设置字幕显示模式
  Future<void> _setSubtitleMode(SubtitleDisplayMode mode) async {
    if (!mounted) return;

    setState(() {
      _subtitleMode = mode;
      // 切换模式时清除当前显示的字幕文本
      if (mode != SubtitleDisplayMode.external) {
        _currentSubtitleText = '';
      }
    });

    switch (mode) {
      case SubtitleDisplayMode.off:
        // 关闭字幕：设置 media_kit 字幕轨为 no
        await _player?.setSubtitleTrack(SubtitleTrack.no());
        break;
      case SubtitleDisplayMode.embedded:
        // 使用内嵌字幕：选择第一条可用轨
        if (_embeddedSubtitleTracks.isNotEmpty) {
          // 优先选择非 "no" 的轨道
          final track = _embeddedSubtitleTracks.firstWhere(
            (t) => t.id != 'no',
            orElse: () => SubtitleTrack.auto(),
          );
          _currentSubtitleTrack = track;
          await _player?.setSubtitleTrack(track);
        } else {
          await _player?.setSubtitleTrack(SubtitleTrack.auto());
        }
        break;
      case SubtitleDisplayMode.external:
        // 外部字幕：关闭 media_kit 内嵌字幕，使用自定义覆盖层
        await _player?.setSubtitleTrack(SubtitleTrack.no());
        // 立即根据当前位置更新字幕
        final position = _player?.state.position ?? Duration.zero;
        final text = SubtitleService.findSubtitleText(_externalCues, position);
        if (mounted) {
          setState(() {
            _currentSubtitleText = text;
          });
        }
        break;
    }
  }

  /// 选择指定的内嵌字幕轨
  Future<void> _setSubtitleTrack(SubtitleTrack track) async {
    _currentSubtitleTrack = track;
    await _player?.setSubtitleTrack(track);
    if (mounted) {
      setState(() {
        _subtitleMode = SubtitleDisplayMode.embedded;
        _currentSubtitleText = '';
      });
    }
  }

  /// 从 URL 加载外部字幕
  Future<bool> _loadExternalSubtitle(String url) async {
    if (_loadedSubtitleUrl == url && _externalCues.isNotEmpty) {
      return true;
    }
    try {
      final cues = await SubtitleService.loadFromUrl(url);
      if (cues.isNotEmpty) {
        _externalCues = cues;
        _loadedSubtitleUrl = url;
        if (mounted) {
          setState(() {});
        }
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// 清除外部字幕
  void _clearExternalSubtitle() {
    _externalCues = [];
    _loadedSubtitleUrl = null;
    if (_subtitleMode == SubtitleDisplayMode.external) {
      _setSubtitleMode(SubtitleDisplayMode.off);
    }
    if (mounted) {
      setState(() {
        _currentSubtitleText = '';
      });
    }
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  void _setupPip() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _pip.setup(const PipOptions(
      autoEnterEnabled: true,
      aspectRatioX: 16,
      aspectRatioY: 9,
      preferredContentWidth: 480,
      preferredContentHeight: 270,
      controlStyle: 2,
    ));
  }

  void _registerPipObserver() {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    _pip.registerStateChangedObserver(PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        if (!mounted) return;
        switch (state) {
          case PipState.pipStateStarted:
            debugPrint('PiP started successfully');
            if (mounted) {
              setState(() => _isPipMode = true);
              widget.onPipModeChanged?.call(true);
            }
            break;
          case PipState.pipStateStopped:
            debugPrint('PiP stopped');
            if (mounted) {
              setState(() {
                _isPipMode = false;
              });
              widget.onPipModeChanged?.call(false);
            }
            break;
          case PipState.pipStateFailed:
            debugPrint('PiP failed: $error');
            if (mounted) {
              setState(() => _isPipMode = false);
              widget.onPipModeChanged?.call(false);
            }
            break;
        }
      },
    ));
  }

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    try {
      var support = await _pip.isSupported();
      if (!support) {
        debugPrint('Device does not support PiP!');
        return;
      }
      await _player?.play();
      await _pip.start();
    } catch (e) {
      debugPrint('Failed to enter PiP mode: $e');
      _setupPip();
    }
  }

  Future<void> _externalDispose() async {
    if (!mounted || _playerDisposed) {
      return;
    }
    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _playerDisposed = true;
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();
    _tracksSubscription?.cancel();
    _progressListeners.clear();
    await _player?.dispose();
    _player = null;
    _videoController = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid || Platform.isIOS) {
      _pip.unregisterStateChangedObserver();
      _pip.dispose();
    }
    _disposePlayer();
    _playbackSpeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? Stack(
              children: [
                Video(
                  controller: _videoController!,
                  controls: (state) {
                    return widget.surface == VideoPlayerSurface.desktop
                        ? PCPlayerControls(
                            state: state,
                            player: _player!,
                            onBackPressed: widget.onBackPressed,
                            onNextEpisode: widget.onNextEpisode,
                            onPause: widget.onPause,
                            videoUrl: _currentUrl ?? '',
                            isLastEpisode: widget.isLastEpisode,
                            isLoadingVideo: _isLoadingVideo,
                            onCastStarted: widget.onCastStarted,
                            videoTitle: widget.videoTitle,
                            currentEpisodeIndex: widget.currentEpisodeIndex,
                            totalEpisodes: widget.totalEpisodes,
                            sourceName: widget.sourceName,
                            onWebFullscreenChanged: widget.onWebFullscreenChanged,
                            onExitWebFullscreenCallbackReady: (callback) {
                              _exitWebFullscreenCallback = callback;
                            },
                            onExitFullScreen: widget.onExitFullScreen,
                            live: widget.live,
                            playbackSpeedListenable: _playbackSpeed,
                            onSetSpeed: _setPlaybackSpeed,
                            // 字幕相关参数
                            subtitleMode: _subtitleMode,
                            embeddedSubtitleTracks: _embeddedSubtitleTracks,
                            currentSubtitleTrack: _currentSubtitleTrack,
                            hasExternalSubtitle: _externalCues.isNotEmpty,
                            onSubtitleModeChanged: _setSubtitleMode,
                            onSubtitleTrackSelected: _setSubtitleTrack,
                            onLoadExternalSubtitle: _loadExternalSubtitle,
                          )
                        : MobilePlayerControls(
                            player: _player!,
                            state: state,
                            onControlsVisibilityChanged: (_) {},
                            onBackPressed: widget.onBackPressed,
                            onFullscreenChange: (_) {},
                            onNextEpisode: widget.onNextEpisode,
                            onPause: widget.onPause,
                            videoUrl: _currentUrl ?? '',
                            isLastEpisode: widget.isLastEpisode,
                            isLoadingVideo: _isLoadingVideo,
                            onCastStarted: widget.onCastStarted,
                            videoTitle: widget.videoTitle,
                            currentEpisodeIndex: widget.currentEpisodeIndex,
                            totalEpisodes: widget.totalEpisodes,
                            sourceName: widget.sourceName,
                            onExitFullScreen: widget.onExitFullScreen,
                            live: widget.live,
                            playbackSpeedListenable: _playbackSpeed,
                            onSetSpeed: _setPlaybackSpeed,
                            onEnterPipMode: _enterPipMode,
                            isPipMode: _isPipMode,
                            // 字幕相关参数
                            subtitleMode: _subtitleMode,
                            embeddedSubtitleTracks: _embeddedSubtitleTracks,
                            currentSubtitleTrack: _currentSubtitleTrack,
                            hasExternalSubtitle: _externalCues.isNotEmpty,
                            onSubtitleModeChanged: _setSubtitleMode,
                            onSubtitleTrackSelected: _setSubtitleTrack,
                            onLoadExternalSubtitle: _loadExternalSubtitle,
                          );
                  },
                ),
                // 外部字幕覆盖层（仅在 external 模式且有字幕文本时显示）
                if (_subtitleMode == SubtitleDisplayMode.external &&
                    _currentSubtitleText.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 60,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _currentSubtitleText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              shadows: [
                                Shadow(
                                  color: Colors.black,
                                  offset: Offset(1, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }
}
