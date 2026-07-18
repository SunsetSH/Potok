import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/db/database.dart';
import 'capture_sheet.dart';
import 'providers.dart';
import 'snackbars.dart';

/// Фокус сейчас в текстовом вводе (TextField/Quill)? Такие шорткаты, как
/// Delete и Esc, не должны конфликтовать с редактированием текста.
bool isTextEditingFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorStateOfType<EditableTextState>() != null ||
      context.findAncestorWidgetOfExactType<QuillEditor>() != null;
}

class _NewNoteIntent extends Intent {
  const _NewNoteIntent();
}

class _NewAudioNoteIntent extends Intent {
  const _NewAudioNoteIntent();
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}

class _FlushNoteIntent extends Intent {
  const _FlushNoteIntent();
}

class _DeleteSelectedNoteIntent extends Intent {
  const _DeleteSelectedNoteIntent();
}

/// Горячие клавиши приложения (ТЗ 0.6.6): Ctrl+N — текстовый quick capture,
/// Ctrl+Shift+N — quick capture с записью аудио, Ctrl+K — фокус поиска,
/// Ctrl+S — немедленный durable flush документа (FR-NOT-006),
/// Delete — выбранная заметка в корзину (только вне текстовых полей).
/// Обёртка выше Navigator, работает на всех экранах.
class AppShortcuts extends ConsumerWidget {
  final Widget child;

  const AppShortcuts({super.key, required this.child});

  void _openCapture({required bool startWithAudio}) {
    final navigatorContext = appNavigatorKey.currentContext;
    if (navigatorContext != null) {
      unawaited(
        showCaptureSheet(navigatorContext, startWithAudio: startWithAudio),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _NewNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
            _NewAudioNoteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _FocusSearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _FlushNoteIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _DeleteSelectedNoteIntent(),
      },
      child: Actions(
        actions: {
          _NewNoteIntent: CallbackAction<_NewNoteIntent>(
            onInvoke: (_) {
              _openCapture(startWithAudio: false);
              return null;
            },
          ),
          _NewAudioNoteIntent: CallbackAction<_NewAudioNoteIntent>(
            onInvoke: (_) {
              _openCapture(startWithAudio: true);
              return null;
            },
          ),
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              ref.read(searchFocusProvider).requestFocus();
              return null;
            },
          ),
          _FlushNoteIntent: CallbackAction<_FlushNoteIntent>(
            onInvoke: (_) {
              unawaited(
                ref.read(noteFlushRegistryProvider).flushNow().catchError((
                  Object e,
                ) {
                  debugPrint('ctrl+s flush failed: ${e.runtimeType}');
                }),
              );
              return null;
            },
          ),
          _DeleteSelectedNoteIntent: _DeleteSelectedNoteAction(ref),
        },
        child: child,
      ),
    );
  }
}

/// Delete → корзина с Undo. Действие отключено, когда фокус в текстовом
/// вводе или открыт диалог/детальный экран (заметка «в списке», ТЗ 0.6.6);
/// отключённое действие пропускает клавишу дальше (удаление символа в поле).
class _DeleteSelectedNoteAction extends Action<_DeleteSelectedNoteIntent> {
  final WidgetRef ref;

  _DeleteSelectedNoteAction(this.ref);

  @override
  bool get isActionEnabled {
    final navigator = appNavigatorKey.currentState;
    // canPop: открыт диалог или detail-роут — Delete относится не к списку.
    if (navigator == null || navigator.canPop()) return false;
    if (isTextEditingFocused()) return false;
    return ref.read(selectedNoteIdProvider) != null;
  }

  @override
  Object? invoke(_DeleteSelectedNoteIntent intent) {
    unawaited(_moveToTrash());
    return null;
  }

  Future<void> _moveToTrash() async {
    final id = ref.read(selectedNoteIdProvider);
    if (id == null) return;
    final messenger = appScaffoldMessengerKey.currentState;
    try {
      final service = await ref.read(notesServiceProvider.future);
      // Свежая строка из БД: selectedNoteProvider ленив и мог не успеть
      // выдать значение к моменту нажатия клавиши.
      final rows = await service.getNotesByIds({id});
      final note = rows.isEmpty ? null : rows.first;
      if (note == null || note.deletedAtUtc != null) return;
      await service.moveToTrash(note);
      // Свежая строка (новая ревизия) — иначе Undo упадёт на stale revision.
      final trashed = (await service.getNotesByIds({note.id})).single;
      ref.read(selectedNoteIdProvider.notifier).select(null);
      messenger?.showSnackBar(
        PotokSnackBar(
          content: const Text('Заметка перемещена в корзину'),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () => unawaited(_restore(trashed)),
          ),
        ),
      );
    } on StateError {
      messenger?.showSnackBar(
        PotokSnackBar(
          content: const Text('Заметка изменилась — список обновлён'),
        ),
      );
    } catch (e) {
      debugPrint('delete shortcut failed: ${e.runtimeType}');
      messenger?.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось удалить заметку')),
      );
    }
  }

  Future<void> _restore(Note trashed) async {
    try {
      final service = await ref.read(notesServiceProvider.future);
      await service.restoreFromTrash(trashed);
    } catch (e) {
      debugPrint('undo trash failed: ${e.runtimeType}');
      appScaffoldMessengerKey.currentState?.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось восстановить заметку')),
      );
    }
  }
}
