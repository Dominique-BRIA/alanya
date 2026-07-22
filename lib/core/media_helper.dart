import 'package:flutter/material.dart';

enum AlanyaMediaType {
  image, video, audio, pdf, word, excel, powerpoint, text, link, unknown,
}

class LinkMeta {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String? favicon;

  const LinkMeta({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    this.favicon,
  });
}

class MediaHelper {
  MediaHelper._();

  static AlanyaMediaType detectType(String? mimeType, String? fileName) {
    final mime = (mimeType ?? '').toLowerCase();
    final name = (fileName ?? '').toLowerCase();
    if (mime.startsWith('image/')) return AlanyaMediaType.image;
    if (mime.startsWith('video/')) return AlanyaMediaType.video;
    if (mime.startsWith('audio/')) return AlanyaMediaType.audio;
    if (mime == 'application/pdf' || name.endsWith('.pdf')) return AlanyaMediaType.pdf;
    if (mime.contains('word') || name.endsWith('.doc') || name.endsWith('.docx')) return AlanyaMediaType.word;
    if (mime.contains('sheet') || mime.contains('excel') || name.endsWith('.xls') || name.endsWith('.xlsx')) return AlanyaMediaType.excel;
    if (mime.contains('presentation') || mime.contains('powerpoint') || name.endsWith('.ppt') || name.endsWith('.pptx')) return AlanyaMediaType.powerpoint;
    if (mime.startsWith('text/')) return AlanyaMediaType.text;
    return AlanyaMediaType.unknown;
  }

  static String? extractUrl(String text) {
    final urlRegex = RegExp('https?://[^\\s<>"\')\\]]+', caseSensitive: false);
    final match = urlRegex.firstMatch(text);
    return match?.group(0);
  }

  static IconData iconForType(AlanyaMediaType type) {
    switch (type) {
      case AlanyaMediaType.image: return Icons.image;
      case AlanyaMediaType.video: return Icons.videocam;
      case AlanyaMediaType.audio: return Icons.headphones;
      case AlanyaMediaType.pdf: return Icons.picture_as_pdf;
      case AlanyaMediaType.word: return Icons.description;
      case AlanyaMediaType.excel: return Icons.table_chart;
      case AlanyaMediaType.powerpoint: return Icons.slideshow;
      case AlanyaMediaType.text: return Icons.text_snippet;
      case AlanyaMediaType.link: return Icons.link;
      case AlanyaMediaType.unknown: return Icons.insert_drive_file;
    }
  }

  static Color colorForType(AlanyaMediaType type) {
    switch (type) {
      case AlanyaMediaType.pdf: return const Color(0xFFE53935);
      case AlanyaMediaType.word: return const Color(0xFF2196F3);
      case AlanyaMediaType.excel: return const Color(0xFF4CAF50);
      case AlanyaMediaType.powerpoint: return const Color(0xFFFF9800);
      case AlanyaMediaType.video: return const Color(0xFF9C27B0);
      case AlanyaMediaType.audio: return const Color(0xFF00BCD4);
      default: return const Color(0xFF757575);
    }
  }

  static String formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
  }

  static String formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '';
    final totalSec = ms ~/ 1000;
    final min = totalSec ~/ 60;
    final sec = totalSec % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  static String extension(String? fileName) {
    if (fileName == null) return '';
    final parts = fileName.split('.');
    return parts.length > 1 ? '.${parts.last}' : '';
  }
}
