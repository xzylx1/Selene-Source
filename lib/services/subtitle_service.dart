import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/subtitle_cue.dart';

/// 字幕解析服务
///
/// 支持解析 SRT 和 WebVTT 格式的字幕文件，
/// 可从 URL 加载字幕内容并解析为 [SubtitleCue] 列表。
class SubtitleService {
  static const Duration _timeout = Duration(seconds: 15);

  /// 从 URL 加载并解析字幕
  ///
  /// 返回解析后的字幕条目列表，失败时返回空列表。
  static Future<List<SubtitleCue>> loadFromUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }

      // 尝试 UTF-8 解码，失败则使用 latin1
      String content;
      try {
        content = utf8.decode(response.bodyBytes, allowMalformed: false);
      } catch (_) {
        content = latin1.decode(response.bodyBytes, allowInvalid: true);
      }

      return parse(content);
    } catch (_) {
      return [];
    }
  }

  /// 解析字幕内容（自动识别 SRT / VTT）
  static List<SubtitleCue> parse(String content) {
    final type = subtitleTypeFromContent(content);
    switch (type) {
      case SubtitleType.vtt:
        return parseVtt(content);
      case SubtitleType.srt:
      default:
        return parseSrt(content);
    }
  }

  /// 解析 SRT 格式字幕
  ///
  /// SRT 格式示例：
  /// ```
  /// 1
  /// 00:00:01,000 --> 00:00:04,000
  /// 第一行字幕
  /// 第二行字幕
  ///
  /// 2
  /// 00:00:05,000 --> 00:00:08,000
  /// ...
  /// ```
  static List<SubtitleCue> parseSrt(String content) {
    final cues = <SubtitleCue>[];
    // 标准化换行符
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    // 按空行分割成块
    final blocks = normalized.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) continue;

      // 找到时间轴行（包含 "-->"）
      Duration? start;
      Duration? end;
      int textStartIndex = -1;

      for (int i = 0; i < lines.length; i++) {
        final match = _srtTimePattern.firstMatch(lines[i]);
        if (match != null) {
          start = _parseSrtTime(match.group(1)!);
          end = _parseSrtTime(match.group(2)!);
          textStartIndex = i + 1;
          break;
        }
      }

      if (start == null || end == null || textStartIndex < 0) continue;

      final textLines = lines.sublist(textStartIndex);
      if (textLines.isEmpty) continue;

      final text = textLines
          .map((l) => l.trim())
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), ''); // 去除 HTML 标签

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    return cues;
  }

  /// SRT 时间轴匹配正则
  static final RegExp _srtTimePattern = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[,.]\d{1,3})',
  );

  /// 解析 SRT 时间字符串，如 "00:00:01,000" 或 "0:0:1.000"
  static Duration _parseSrtTime(String timeStr) {
    final parts = timeStr.trim().split(':');
    if (parts.length != 3) return Duration.zero;

    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;

    // 秒和毫秒用 , 或 . 分隔
    final secMs = parts[2].split(RegExp(r'[,.]'));
    final seconds = int.tryParse(secMs[0]) ?? 0;
    final ms = secMs.length > 1 ? int.tryParse(secMs[1].padRight(3, '0')) ?? 0 : 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: ms,
    );
  }

  /// 解析 WebVTT 格式字幕
  ///
  /// VTT 格式示例：
  /// ```
  /// WEBVTT
  ///
  /// 1
  /// 00:00:01.000 --> 00:00:04.000
  /// 第一行字幕
  ///
  /// 2
  /// 00:00:05.000 --> 00:00:08.000
  /// ...
  /// ```
  static List<SubtitleCue> parseVtt(String content) {
    final cues = <SubtitleCue>[];
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;

      // 跳过 WEBVTT 头
      if (lines.any((l) => l.trim().toUpperCase() == 'WEBVTT')) {
        if (lines.length == 1) continue;
      }

      Duration? start;
      Duration? end;
      int textStartIndex = -1;

      for (int i = 0; i < lines.length; i++) {
        final match = _vttTimePattern.firstMatch(lines[i]);
        if (match != null) {
          start = _parseVttTime(match.group(1)!);
          end = _parseVttTime(match.group(2)!);
          textStartIndex = i + 1;
          break;
        }
      }

      if (start == null || end == null || textStartIndex < 0) continue;

      final textLines = lines.sublist(textStartIndex);
      if (textLines.isEmpty) continue;

      final text = textLines
          .map((l) => l.trim())
          .join('\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll(RegExp(r'&nbsp;'), ' ');

      cues.add(SubtitleCue(start: start, end: end, text: text));
    }

    return cues;
  }

  /// VTT 时间轴匹配正则（支持 MM:SS.mmm 或 HH:MM:SS.mmm）
  static final RegExp _vttTimePattern = RegExp(
    r'(\d{1,2}:\d{2}(?::\d{2})?\.\d{1,3})\s*-->\s*(\d{1,2}:\d{2}(?::\d{2})?\.\d{1,3})',
  );

  /// 解析 VTT 时间字符串
  static Duration _parseVttTime(String timeStr) {
    final trimmed = timeStr.trim();
    final colonCount = ':'.allMatches(trimmed).length;

    String hours = '0';
    String minutes;
    String seconds;
    String ms = '0';

    if (colonCount == 2) {
      // HH:MM:SS.mmm
      final parts = trimmed.split(':');
      hours = parts[0];
      minutes = parts[1];
      final secMs = parts[2].split('.');
      seconds = secMs[0];
      ms = secMs.length > 1 ? secMs[1].padRight(3, '0') : '0';
    } else {
      // MM:SS.mmm
      final parts = trimmed.split(':');
      minutes = parts[0];
      final secMs = parts[1].split('.');
      seconds = secMs[0];
      ms = secMs.length > 1 ? secMs[1].padRight(3, '0') : '0';
    }

    return Duration(
      hours: int.tryParse(hours) ?? 0,
      minutes: int.tryParse(minutes) ?? 0,
      seconds: int.tryParse(seconds) ?? 0,
      milliseconds: int.tryParse(ms) ?? 0,
    );
  }

  /// 在字幕列表中查找指定时间点对应的字幕文本
  ///
  /// 使用二分查找提高效率，返回空字符串表示当前无字幕。
  static String findSubtitleText(List<SubtitleCue> cues, Duration time) {
    if (cues.isEmpty) return '';

    int lo = 0;
    int hi = cues.length - 1;

    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      final cue = cues[mid];

      if (time < cue.start) {
        hi = mid - 1;
      } else if (time > cue.end) {
        lo = mid + 1;
      } else {
        return cue.text;
      }
    }

    return '';
  }
}
