import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_theme.dart';

enum FileExportMode { save, share }

Future<void> exportUserFile(
  BuildContext context, {
  required String title,
  required String fileName,
  required String mimeType,
  required List<int> bytes,
  List<String>? allowedExtensions,
}) async {
  final mode = await showModalBottomSheet<FileExportMode>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => _ExportSheet(title: title),
  );
  if (mode == null || !context.mounted) return;

  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  if (mode == FileExportMode.save) {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: title,
        fileName: fileName,
        type: allowedExtensions == null ? FileType.any : FileType.custom,
        allowedExtensions: allowedExtensions,
        bytes: data,
      );
      if (!context.mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved on this phone.')),
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save that file.')),
        );
      }
    }
    return;
  }

  try {
    await Share.shareXFiles([
      XFile.fromData(data, mimeType: mimeType, name: fileName),
    ]);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share that file.')),
      );
    }
  }
}

class _ExportSheet extends StatelessWidget {
  const _ExportSheet({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: EdgeInsets.fromLTRB(
        8,
        16,
        8,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: p.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: p.textHigh,
                ),
              ),
            ),
          ),
          _Choice(
            palette: p,
            icon: Icons.save_alt_rounded,
            label: 'Save on this phone',
            subtitle: 'Choose a folder, like Downloads',
            onTap: () => Navigator.pop(context, FileExportMode.save),
          ),
          _Choice(
            palette: p,
            icon: Icons.ios_share_rounded,
            label: 'Share',
            subtitle: 'Send to Drive, email, or another app',
            onTap: () => Navigator.pop(context, FileExportMode.share),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.palette,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final AppPalette palette;
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: palette.accent),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: palette.textHigh,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: palette.textMid,
        ),
      ),
    );
  }
}

Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));
