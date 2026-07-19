import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'asr_model_catalog_view.dart';
import 'providers.dart';
import 'theme.dart';

/// Оборачивает корневой экран: после первого кадра проверяет, установлена ли
/// хоть одна ASR-модель, и если нет — предлагает выбрать и скачать. Приложение
/// не несёт встроенной модели, поэтому это единственный способ получить
/// расшифровку речи из коробки, — актуально и для Windows, и для Android.
class AsrFirstRunGate extends ConsumerStatefulWidget {
  final Widget child;

  const AsrFirstRunGate({super.key, required this.child});

  @override
  ConsumerState<AsrFirstRunGate> createState() => _AsrFirstRunGateState();
}

class _AsrFirstRunGateState extends ConsumerState<AsrFirstRunGate> {
  var _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePrompt());
  }

  Future<void> _maybePrompt() async {
    if (_checked || !mounted) return;
    _checked = true;
    try {
      final manager = await ref.read(modelManagerProvider.future);
      // Уже есть выбор (установленный пак или dev-fallback) — не мешаем.
      if (await manager.activeModelDir() != null) return;
      final installed = await manager.listInstalled();
      if (installed.isNotEmpty || !mounted) return;
      await showAsrFirstRunDialog(context);
    } catch (error) {
      // Сбой проверки не должен ронять запуск приложения — просто не
      // покажем предложение, пользователь всегда может открыть настройки.
      debugPrint('asr first-run check failed: ${error.runtimeType}');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showAsrFirstRunDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const _AsrFirstRunDialog(),
  );
}

class _AsrFirstRunDialog extends StatelessWidget {
  const _AsrFirstRunDialog();

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return Dialog(
      backgroundColor: c.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Выберите модель распознавания речи',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Голосовые заметки расшифровываются локально, без интернета. '
                'Скачайте модель — можно и позже, в настройках («Распознавание речи»).',
                style: TextStyle(fontSize: 12, color: c.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: AsrModelCatalogView(
                    onModelActivated: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Настроить позже'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
