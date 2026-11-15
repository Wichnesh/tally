import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

const _imageTypes = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp'];

/// Small preview of one proof file. Click to open it.
/// Shows a remove (x) button when [onRemove] is given.
class ProofTile extends StatelessWidget {
  final String path;
  final VoidCallback? onRemove;
  const ProofTile(this.path, {super.key, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isImage = _imageTypes.contains(p.extension(path).toLowerCase());
    final name = p.basename(path).replaceFirst(RegExp(r'^\d+_'), '');

    return SizedBox(
      width: 110,
      child: Stack(
        children: [
          InkWell(
            onTap: () => launchUrl(Uri.file(path)),
            borderRadius: BorderRadius.circular(8),
            child: Column(
              children: [
                Container(
                  height: 80,
                  width: 110,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isImage
                      ? Image.file(File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.broken_image))
                      : Icon(
                          p.extension(path).toLowerCase() == '.pdf'
                              ? Icons.picture_as_pdf
                              : Icons.insert_drive_file,
                          size: 36),
                ),
                const SizedBox(height: 4),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          if (onRemove != null)
            Positioned(
              right: 2,
              top: 2,
              child: IconButton.filled(
                tooltip: 'Remove',
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ),
        ],
      ),
    );
  }
}
