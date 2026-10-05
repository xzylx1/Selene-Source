/// 字幕条目数据模型
class SubtitleCue {
  /// 开始时间
  final Duration start;

  /// 结束时间
  final Duration end;

  /// 字幕文本（支持多行，用 \n 分隔）
  final String text;

  SubtitleCue({
    required this.start,
    required this.end,
    required this.text,
  });

  /// 判断指定时间点是否在该字幕条目的时间范围内
  bool contains(Duration time) {
    return time >= start && time <= end;
  }

  @override
  String toString() =>
      'SubtitleCue(start: $start, end: $end, text: $text)';
}

/// 字幕类型枚举
enum SubtitleType {
  /// SRT 格式
  srt,

  /// WebVTT 格式
  vtt,

  /// 未知格式
  unknown,
}

/// 从文件扩展名或 URL 推断字幕类型
SubtitleType subtitleTypeFromUrl(String url) {
  final lower = url.toLowerCase();
  if (lower.endsWith('.srt')) return SubtitleType.srt;
  if (lower.endsWith('.vtt')) return SubtitleType.vtt;
  return SubtitleType.unknown;
}

/// 从内容推断字幕类型
SubtitleType subtitleTypeFromContent(String content) {
  final trimmed = content.trimLeft();
  if (trimmed.startsWith('WEBVTT')) return SubtitleType.vtt;
  return SubtitleType.srt;
}
