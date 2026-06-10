import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_state.dart';
import '../design_system.dart';
import '../main.dart';
import '../models.dart';
import 'import_screen.dart';
import 'session_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: appState.load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  _HomeTopBar(
                    onSettings: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  if (appState.errorMessage != null)
                    _ErrorBanner(message: appState.errorMessage!),
                  if (appState.isBusy && appState.sessions.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (appState.sessions.isEmpty)
                    const _EmptyHome()
                  else ...[
                    _SectionHeader(
                      title: 'Sessions',
                      subtitle: '${appState.sessions.length} active',
                    ),
                    const SizedBox(height: 12),
                    for (final session in appState.sessions) ...[
                      _SessionTile(session: session),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import CSV'),
          ),
        );
      },
    );
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AppIconTile(
          icon: Icons.psychology_alt_outlined,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LLM Recall', style: Theme.of(context).textTheme.titleLarge),
              Text(
                'Review sessions',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.tune_outlined),
          onPressed: onSettings,
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final PreAnkiSession session;

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    final updated = DateFormat.yMMMd().add_jm().format(session.updatedAt);
    return AppSurface(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionScreen(sessionId: session.id!),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconTile(
                icon: Icons.style_outlined,
                color: AppColors.accentSky,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Session actions',
                onSelected: (value) async {
                  if (value == 'rename') {
                    await _renameSession(context, appState, session);
                  } else if (value == 'restart') {
                    await appState.restartSession(session.id!);
                  } else if (value == 'export') {
                    final path = await appState.exportSession(session.id!);
                    if (!context.mounted || path == null) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Exported to $path')),
                    );
                  } else if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete session?'),
                        content: Text(
                          'This removes "${session.title}" and its cards.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await appState.deleteSession(session.id!);
                    }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('Export CSV'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restart',
                    child: ListTile(
                      leading: Icon(Icons.replay_outlined),
                      title: Text('Restart'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.full),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: session.progress,
              backgroundColor: AppColors.hairline,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppBadge(
                icon: Icons.style_outlined,
                label: '${session.totalCards} cards',
                color: AppColors.inkMuted,
              ),
              AppBadge(
                icon: Icons.school_outlined,
                label: '${session.learningCount} learning',
                color: AppColors.accentOrange,
              ),
              AppBadge(
                icon: Icons.task_alt_outlined,
                label: '${session.learnedCount} learned',
              ),
              AppBadge(
                icon: Icons.delete_outline,
                label: '${session.deletedCount} deleted',
                color: AppColors.danger,
              ),
              AppBadge(
                icon: Icons.schedule_outlined,
                label: updated,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AppSurface(
            child: Column(
              children: [
                const AppIconTile(
                  icon: Icons.upload_file_outlined,
                  color: AppColors.accentPurple,
                ),
                const SizedBox(height: 16),
                Text(
                  'Import your first CSV.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _renameSession(
  BuildContext context,
  PreAnkiAppState appState,
  PreAnkiSession session,
) async {
  final controller = TextEditingController(text: session.title);
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename session'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Session name',
          prefixIcon: Icon(Icons.drive_file_rename_outline),
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (title == null || title.trim().isEmpty || !context.mounted) {
    return;
  }
  await appState.renameSession(session.id!, title);
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
