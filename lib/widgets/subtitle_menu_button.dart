import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'video_player_widget.dart';

/// 字幕菜单按钮
///
/// 统一的字幕控制入口，供 PC 端和移动端播放器控制栏复用。
/// 点击后弹出菜单，支持：
/// - 关闭字幕
/// - 选择内嵌字幕轨（视频自带的字幕）
/// - 加载外部字幕（从 URL 加载 SRT / VTT 文件）
class SubtitleMenuButton extends StatefulWidget {
  /// 当前字幕显示模式
  final SubtitleDisplayMode subtitleMode;

  /// 可用的内嵌字幕轨列表
  final List<SubtitleTrack> embeddedSubtitleTracks;

  /// 当前选中的内嵌字幕轨
  final SubtitleTrack? currentSubtitleTrack;

  /// 是否已加载外部字幕
  final bool hasExternalSubtitle;

  /// 字幕模式变更回调
  final Future<void> Function(SubtitleDisplayMode mode) onSubtitleModeChanged;

  /// 选择内嵌字幕轨回调
  final Future<void> Function(SubtitleTrack track) onSubtitleTrackSelected;

  /// 加载外部字幕回调，返回是否成功
  final Future<bool> Function(String url) onLoadExternalSubtitle;

  /// 图标大小
  final double iconSize;

  const SubtitleMenuButton({
    super.key,
    required this.subtitleMode,
    required this.embeddedSubtitleTracks,
    required this.currentSubtitleTrack,
    required this.hasExternalSubtitle,
    required this.onSubtitleModeChanged,
    required this.onSubtitleTrackSelected,
    required this.onLoadExternalSubtitle,
    this.iconSize = 22,
  });

  @override
  State<SubtitleMenuButton> createState() => _SubtitleMenuButtonState();
}

class _SubtitleMenuButtonState extends State<SubtitleMenuButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isActive = widget.subtitleMode != SubtitleDisplayMode.off;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: _showSubtitleMenu,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: _isHovering
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.withOpacity(0.5),
                )
              : null,
          child: Icon(
            Icons.closed_caption,
            color: isActive ? Colors.amberAccent : Colors.white,
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }

  /// 显示字幕选择菜单
  void _showSubtitleMenu() async {
    final result = await showModalBottomSheet<SubtitleMenuResult>(
      context: context,
      backgroundColor: const Color(0xFF1a1a1a),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _SubtitleMenuSheet(
        subtitleMode: widget.subtitleMode,
        embeddedSubtitleTracks: widget.embeddedSubtitleTracks,
        currentSubtitleTrack: widget.currentSubtitleTrack,
        hasExternalSubtitle: widget.hasExternalSubtitle,
        onLoadExternalSubtitle: widget.onLoadExternalSubtitle,
      ),
    );

    if (result == null || !mounted) return;

    switch (result.action) {
      case SubtitleMenuAction.turnOff:
        widget.onSubtitleModeChanged(SubtitleDisplayMode.off);
        break;
      case SubtitleMenuAction.useEmbedded:
        widget.onSubtitleModeChanged(SubtitleDisplayMode.embedded);
        break;
      case SubtitleMenuAction.useExternal:
        widget.onSubtitleModeChanged(SubtitleDisplayMode.external);
        break;
      case SubtitleMenuAction.selectTrack:
        if (result.track != null) {
          widget.onSubtitleTrackSelected(result.track!);
        }
        break;
    }
  }
}

/// 字幕菜单操作类型
enum SubtitleMenuAction {
  turnOff,
  useEmbedded,
  useExternal,
  selectTrack,
}

/// 字幕菜单返回结果
class SubtitleMenuResult {
  final SubtitleMenuAction action;
  final SubtitleTrack? track;

  const SubtitleMenuResult(this.action, {this.track});
}

/// 字幕菜单底部弹窗内容
class _SubtitleMenuSheet extends StatefulWidget {
  final SubtitleDisplayMode subtitleMode;
  final List<SubtitleTrack> embeddedSubtitleTracks;
  final SubtitleTrack? currentSubtitleTrack;
  final bool hasExternalSubtitle;
  final Future<bool> Function(String url) onLoadExternalSubtitle;

  const _SubtitleMenuSheet({
    required this.subtitleMode,
    required this.embeddedSubtitleTracks,
    required this.currentSubtitleTrack,
    required this.hasExternalSubtitle,
    required this.onLoadExternalSubtitle,
  });

  @override
  State<_SubtitleMenuSheet> createState() => _SubtitleMenuSheetState();
}

class _SubtitleMenuSheetState extends State<_SubtitleMenuSheet> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoadingUrl = false;
  String? _loadError;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 过滤出可用的内嵌字幕轨（排除 no 轨）
    final realTracks = widget.embeddedSubtitleTracks
        .where((t) => t.id != 'no')
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '字幕设置',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white24),

            // 关闭字幕
            _buildOptionTile(
              icon: Icons.closed_caption_disabled,
              title: '关闭字幕',
              selected: widget.subtitleMode == SubtitleDisplayMode.off,
              onTap: () => Navigator.pop(
                context,
                const SubtitleMenuResult(SubtitleMenuAction.turnOff),
              ),
            ),

            // 内嵌字幕轨列表
            if (realTracks.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  '内嵌字幕',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
              ...realTracks.map((track) => _buildOptionTile(
                    icon: Icons.subtitles,
                    title: _trackTitle(track),
                    selected: widget.currentSubtitleTrack?.id == track.id &&
                        widget.subtitleMode == SubtitleDisplayMode.embedded,
                    onTap: () => Navigator.pop(
                      context,
                      SubtitleMenuResult(
                        SubtitleMenuAction.selectTrack,
                        track: track,
                      ),
                    ),
                  )),
            ],

            // 外部字幕
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                '外部字幕',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            if (widget.hasExternalSubtitle)
              _buildOptionTile(
                icon: Icons.link,
                title: '使用已加载的外部字幕',
                selected:
                    widget.subtitleMode == SubtitleDisplayMode.external,
                onTap: () => Navigator.pop(
                  context,
                  const SubtitleMenuResult(SubtitleMenuAction.useExternal),
                ),
              ),

            // 从 URL 加载
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _urlController,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: '输入字幕文件 URL (.srt / .vtt)',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _loadError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingUrl ? null : _handleLoadUrl,
                      icon: _isLoadingUrl
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download, size: 18),
                      label: Text(_isLoadingUrl ? '加载中...' : '加载字幕'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建选项条目
  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon,
          color: selected ? Colors.amberAccent : Colors.white70, size: 20),
      title: Text(
        title,
        style: TextStyle(
          color: selected ? Colors.amberAccent : Colors.white,
          fontSize: 15,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, color: Colors.amberAccent, size: 18)
          : null,
    );
  }

  /// 处理从 URL 加载字幕
  Future<void> _handleLoadUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _loadError = '请输入字幕 URL');
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _loadError = 'URL 必须以 http:// 或 https:// 开头');
      return;
    }

    setState(() {
      _isLoadingUrl = true;
      _loadError = null;
    });

    final success = await widget.onLoadExternalSubtitle(url);

    if (!mounted) return;

    setState(() => _isLoadingUrl = false);

    if (success) {
      // 加载成功，关闭弹窗并切换到外部字幕模式
      Navigator.pop(
        context,
        const SubtitleMenuResult(SubtitleMenuAction.useExternal),
      );
    } else {
      setState(() => _loadError = '字幕加载失败，请检查 URL 是否正确');
    }
  }

  /// 获取字幕轨显示标题
  String _trackTitle(SubtitleTrack track) {
    final lang = track.language;
    final title = track.title;
    if (title != null && title.isNotEmpty) {
      return lang != null && lang.isNotEmpty ? '$title ($lang)' : title;
    }
    if (lang != null && lang.isNotEmpty) return lang;
    return '字幕轨 ${track.id}';
  }
}
