import 'package:flutter/material.dart';

import 'app_state.dart';
import 'design_system.dart';
import 'import_bridge.dart';
import 'repository.dart';
import 'screens/home_screen.dart';
import 'screens/import_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = PreAnkiRepository();
  await repository.initialize();
  final appState = PreAnkiAppState(repository: repository);
  await appState.load();
  runApp(PreAnkiApp(appState: appState));
}

class PreAnkiApp extends StatefulWidget {
  const PreAnkiApp({super.key, required this.appState});

  final PreAnkiAppState appState;

  @override
  State<PreAnkiApp> createState() => _PreAnkiAppState();
}

class _PreAnkiAppState extends State<PreAnkiApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _importBridge = ImportBridge();

  @override
  void initState() {
    super.initState();
    _importBridge.listen(_openIncomingImport);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialImport = await _importBridge.consumeInitialImport();
      if (initialImport != null && mounted) {
        _openIncomingImport(initialImport);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      appState: widget.appState,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Memory Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        themeMode: ThemeMode.light,
        home: const HomeScreen(),
      ),
    );
  }

  void _openIncomingImport(IncomingCsvImport import) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        return;
      }
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ImportScreen(
            initialCsvText: import.text,
            initialSourceName: import.sourceName,
          ),
        ),
      );
    });
  }
}

class AppScope extends InheritedNotifier<PreAnkiAppState> {
  const AppScope({
    super.key,
    required PreAnkiAppState appState,
    required super.child,
  }) : super(notifier: appState);

  static PreAnkiAppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context.');
    return scope!.notifier!;
  }
}
