import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';

/// Inline document attachment — icon, name, tap to open locally.
class ChatDocumentBubble extends StatefulWidget {
  const ChatDocumentBubble({
    super.key,
    required this.url,
    required this.authToken,
    required this.fileName,
    this.foregroundColor = AppColors.textPrimary,
    this.accentColor = AppColors.violet,
  });

  final String url;
  final String authToken;
  final String fileName;
  final Color foregroundColor;
  final Color accentColor;

  @override
  State<ChatDocumentBubble> createState() => _ChatDocumentBubbleState();
}

class _ChatDocumentBubbleState extends State<ChatDocumentBubble> {
  bool _loading = false;

  IconData get _icon {
    final lower = widget.fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description_rounded;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx')) return Icons.table_chart_rounded;
    if (lower.endsWith('.ppt') || lower.endsWith('.pptx')) return Icons.slideshow_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Future<void> _open() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await http.get(
        Uri.parse(widget.url),
        headers: {
          'Authorization': 'Bearer ${widget.authToken}',
          'Accept': '*/*',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final dir = await getTemporaryDirectory();
      final safeName = widget.fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
      final file = File(p.join(dir.path, safeName));
      await file.writeAsBytes(res.bodyBytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open document')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: widget.accentColor.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: widget.accentColor,
                        ),
                      )
                    : Icon(_icon, color: widget.accentColor, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fileName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.foregroundColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to open',
                      style: TextStyle(
                        color: widget.foregroundColor.withValues(alpha: 0.65),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
