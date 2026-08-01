import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../design_system.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (appState.errorMessage != null) ...[
                  AppErrorBanner(message: appState.errorMessage!),
                  const SizedBox(height: 16),
                ],
                AppSurface(
                  shadow: true,
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const AppIconTile(
                      icon: Icons.folder_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Export folder'),
                    subtitle: Text(appState.defaultExportFolder ?? 'Not set'),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        IconButton(
                          tooltip: 'Choose folder',
                          icon: const Icon(Icons.folder_open_outlined),
                          onPressed: () async {
                            final folder = await FilePicker.getDirectoryPath(
                              dialogTitle: 'Choose export folder',
                              initialDirectory: appState.defaultExportFolder,
                            );
                            if (folder != null) {
                              await appState.setDefaultExportFolder(folder);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Clear folder',
                          icon: const Icon(Icons.close_outlined),
                          onPressed: appState.defaultExportFolder == null
                              ? null
                              : () => appState.setDefaultExportFolder(null),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AppSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const AppIconTile(
                          icon: Icons.inventory_2_outlined,
                          color: AppColors.accentTeal,
                        ),
                        title: const Text('App backup'),
                        subtitle: const Text(
                          'Sessions, cards, review progress, settings',
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: appState.isBusy
                                    ? null
                                    : () => _exportBackup(context),
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Export'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: appState.isBusy
                                    ? null
                                    : () => _importBackup(context),
                                icon: const Icon(
                                  Icons.download_for_offline_outlined,
                                ),
                                label: const Text('Import'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _exportBackup(BuildContext context) async {
  final appState = AppScope.of(context);
  final path = await appState.exportAppBackup();
  if (!context.mounted || path == null) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Backup exported to $path')));
}

Future<void> _importBackup(BuildContext context) async {
  final appState = AppScope.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import backup?'),
      content: const Text('This replaces all local Memory Studio data.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  final imported = await appState.importAppBackup();
  if (!context.mounted || !imported) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Backup imported')));
}
