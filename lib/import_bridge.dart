import 'package:flutter/services.dart';

class IncomingCsvImport {
  const IncomingCsvImport({required this.text, required this.sourceName});

  final String text;
  final String sourceName;

  static IncomingCsvImport? fromPlatform(Object? payload) {
    if (payload is! Map) {
      return null;
    }
    final text = payload['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      return null;
    }
    final sourceName = payload['sourceName']?.toString().trim();
    return IncomingCsvImport(
      text: text,
      sourceName: sourceName != null && sourceName.isNotEmpty
          ? sourceName
          : 'Imported CSV',
    );
  }
}

class ImportBridge {
  const ImportBridge({
    this.channel = const MethodChannel('llm_recall/imports'),
  });

  final MethodChannel channel;

  void listen(void Function(IncomingCsvImport import) onImport) {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'incomingCsv') {
        return null;
      }
      final import = IncomingCsvImport.fromPlatform(call.arguments);
      if (import != null) {
        onImport(import);
      }
      return null;
    });
  }

  Future<IncomingCsvImport?> consumeInitialImport() async {
    try {
      final payload = await channel.invokeMethod<Object?>(
        'consumeInitialImport',
      );
      return IncomingCsvImport.fromPlatform(payload);
    } on MissingPluginException {
      return null;
    }
  }
}
