import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../application/clipboard_image_reader.dart';
import '../application/images_service.dart';
import '../application/notes_service.dart';
import '../domain/document.dart';
import '../domain/types.dart';
import '../infrastructure/audio_player_controller.dart';
import '../infrastructure/db/database.dart';
import 'capture_sheet.dart';
import 'image_paste_intent.dart';
import 'move_note.dart';
import 'providers.dart';
import 'sidebar.dart';
import 'snackbars.dart';
import 'tag_management.dart';
import 'theme.dart';

enum _SaveStatus { saved, saving, error }

/// Detail-панель: toolbar со статусом сохранения, проект, теги,
/// rich-редактор Quill с автосохранением (debounce 500 мс) и аудиоблок
/// с ревизиями.
class NoteDetailPane extends ConsumerStatefulWidget {
  /// Кнопка «назад» на узком макете (панель открыта поверх списка).
  final bool showBack;

  const NoteDetailPane({super.key, this.showBack = false});

  @override
  ConsumerState<NoteDetailPane> createState() => _NoteDetailPaneState();
}

class _NoteDetailPaneState extends ConsumerState<NoteDetailPane> {
  QuillController? _controller;
  StreamSubscription<DocChange>? _docChanges;
  final _editorFocus = FocusNode(debugLabel: 'note-editor');
  final _editorScroll = ScrollController();
  Timer? _debounce;
  String? _noteId;
  Note? _latest;
  Object _noteToken = Object();

  /// documentJson, которому соответствует содержимое редактора: маркер
  /// «есть ли внешнее изменение» и «есть ли что сохранять».
  String? _syncedJson;
  bool _dirty = false;
  bool _saving = false;
  Completer<void>? _saveCompletion;
  _SaveStatus _status = _SaveStatus.saved;

  /// Riverpod запрещает ref в dispose — держим ссылку на реестр в поле.
  late final NoteFlushRegistry _flushRegistry;

  /// Riverpod запрещает ref.read в dispose (ConsumerStatefulElement уже
  /// размонтирован к этому моменту) — держим последний известный сервис
  /// в поле, обновляемое на каждый build().
  NotesService? _notesService;

  @override
  void initState() {
    super.initState();
    // Ctrl+S (FR-NOT-006): глобальный шорткат форсирует durable flush.
    _flushRegistry = ref.read(noteFlushRegistryProvider);
    _flushRegistry.register(_flushNow);
  }

  /// Немедленный durable flush без ожидания debounce; статус обновляет _save.
  Future<void> _flushNow() async {
    if (!mounted) return;
    _debounce?.cancel();
    // Ctrl+S must not merely schedule another debounce when an autosave is
    // already in flight. First wait until that transaction is durable, then
    // persist edits that arrived while it was running.
    final inFlight = _saveCompletion;
    if (inFlight != null) await inFlight.future;
    if (!mounted || !_dirty) return;
    await _save();
  }

  @override
  void dispose() {
    _flushRegistry.unregister(_flushNow);
    _debounce?.cancel();
    _docChanges?.cancel();
    // Панель закрыта с несохранёнными правками — дописываем без ожидания,
    // чтобы правка не потерялась (durable-сразу, ТЗ 0.1). Flush сериализуем
    // с незавершённым автосохранением: параллельная запись со старой
    // ревизией молча падала бы на optimistic-lock (StateError).
    final note = _latest;
    final controller = _controller;
    if (_dirty && note != null && controller != null) {
      final service = _notesService;
      if (service != null) {
        final document = _snapshot(controller);
        final encoded = document.encode();
        final inFlight = _saveCompletion?.future ?? Future<void>.value();
        unawaited(
          inFlight
              .then((_) {
                // _latest/_syncedJson обновлены завершившимся _save —
                // берём актуальную ревизию и не пишем дубликат.
                if (encoded == _syncedJson) return Future<void>.value();
                return service.updateDocument(_latest ?? note, document);
              })
              .catchError((Object e) {
                debugPrint('note flush failed: ${e.runtimeType}');
              }),
        );
      }
    }
    controller?.dispose();
    _editorFocus.dispose();
    _editorScroll.dispose();
    super.dispose();
  }

  /// Снимок Quill-документа в canonical-конверт (ADR-003).
  static PotokDocument _snapshot(QuillController controller) {
    final ops = controller.document.toDelta().toJson();
    return PotokDocument.fromDeltaOps(
      ops
          .map((op) => Map<String, Object?>.from(op as Map))
          .toList(growable: false),
    );
  }

  static Document _quillDocumentFrom(String documentJson) {
    List<Map<String, Object?>> ops;
    try {
      ops = PotokDocument.decode(documentJson).deltaOps;
    } on FormatException catch (e) {
      // Битый документ не должен ронять панель: показываем пустой.
      debugPrint('document decode failed: ${e.runtimeType}');
      ops = const [];
    }
    return ops.isEmpty ? Document() : Document.fromJson(ops);
  }

  void _attachController(String documentJson) {
    _docChanges?.cancel();
    _controller?.dispose();
    final controller = QuillController(
      document: _quillDocumentFrom(documentJson),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _controller = controller;
    _syncedJson = documentJson;
    _docChanges = controller.changes.listen(_onDocChange);
  }

  /// Внешнее изменение (принятая расшифровка, другая панель): подменяем
  /// документ и переподписываемся — поток changes принадлежит документу.
  void _reloadDocument(String documentJson) {
    final controller = _controller;
    if (controller == null) return;
    _docChanges?.cancel();
    controller.document = _quillDocumentFrom(documentJson);
    _syncedJson = documentJson;
    _docChanges = controller.changes.listen(_onDocChange);
  }

  void _sync(Note? note) {
    if (note == null) {
      _noteToken = Object();
      _noteId = null;
      _latest = null;
      _docChanges?.cancel();
      _docChanges = null;
      _controller?.dispose();
      _controller = null;
      _syncedJson = null;
      return;
    }
    if (note.id != _noteId) {
      _noteToken = Object();
      _debounce?.cancel();
      _noteId = note.id;
      _latest = note;
      _dirty = false;
      _saving = false;
      _status = _SaveStatus.saved;
      _attachController(note.documentJson);
      return;
    }
    _latest = note;
    if (!_dirty && !_saving && note.documentJson != _syncedJson) {
      _reloadDocument(note.documentJson);
    }
  }

  void _onDocChange(DocChange change) {
    // Локальные правки: набор текста, toggle чекбокса, вставка embed —
    // всё проходит через автосохранение (FR-DOC-004).
    if (change.source != ChangeSource.local) return;
    _dirty = true;
    if (_status != _SaveStatus.saving) {
      setState(() => _status = _SaveStatus.saving);
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<void> _save() async {
    while (_saving) {
      await _saveCompletion?.future;
      // Пока шло сохранение, могли прийти новые правки — сохраняем и их,
      // иначе вызывающий (Ctrl+S) увидит «сохранено» при _dirty == true.
      if (!mounted || !_dirty) return;
    }
    final note = _latest;
    final controller = _controller;
    if (note == null || controller == null) return;
    final document = _snapshot(controller);
    final encoded = document.encode();
    if (encoded == _syncedJson) {
      setState(() {
        _dirty = false;
        _status = _SaveStatus.saved;
      });
      return;
    }
    _saving = true;
    final completion = Completer<void>();
    _saveCompletion = completion;
    // Правки на момент снимка учтены; новые пометят _dirty заново.
    _dirty = false;
    try {
      await ref
          .read(notesServiceProvider)
          .requireValue
          .updateDocument(note, document);
      // Локально фиксируем новую ревизию, не дожидаясь потока: следующее
      // автосохранение не должно упасть на stale revision.
      _latest = note.copyWith(
        documentJson: encoded,
        documentPlainText: document.plainText,
        revision: note.revision + 1,
      );
      _syncedJson = encoded;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = _dirty ? _SaveStatus.saving : _SaveStatus.saved;
      });
      if (_dirty) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 500), _save);
      }
    } on StateError {
      // Конкурентное изменение: _dirty сброшен — следующий build перечитает
      // актуальную версию из потока.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = _SaveStatus.saved;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        PotokSnackBar(
          content: Text(
            'Заметка изменена в другом месте — показана актуальная версия',
          ),
        ),
      );
    } catch (e) {
      debugPrint('note save failed: ${e.runtimeType}');
      // The snapshot is still present in the editor and must remain
      // retryable (manually with Ctrl+S or by a later edit).
      _dirty = true;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = _SaveStatus.error;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        PotokSnackBar(content: const Text('Не удалось сохранить заметку')),
      );
    } finally {
      _saving = false;
      if (identical(_saveCompletion, completion)) {
        _saveCompletion = null;
      }
      if (!completion.isCompleted) completion.complete();
    }
  }

  /// Кнопка «▧ изображение»: file_selector → attachImage → embed в позицию
  /// курсора (FR-DOC-003).
  Future<void> _insertImage() async {
    final note = _latest;
    if (note == null) return;
    final expectedNoteToken = _noteToken;
    final messenger = ScaffoldMessenger.of(context);
    const typeGroup = XTypeGroup(
      label: 'Изображения',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
    );
    final XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: const [typeGroup]);
    } catch (e) {
      debugPrint('image pick failed: ${e.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось открыть выбор файла')),
      );
      return;
    }
    if (picked == null || !mounted) return;
    try {
      final images = await ref.read(imagesServiceProvider.future);
      final asset = await images.attachImage(note, picked.path);
      final defaultAlt = p.basenameWithoutExtension(picked.path).trim();
      _insertManagedImage(
        asset.id,
        defaultAlt.isEmpty ? 'Изображение' : defaultAlt,
        expectedNoteToken: expectedNoteToken,
      );
    } on ImageAttachException catch (e) {
      messenger.showSnackBar(PotokSnackBar(content: Text(e.message)));
    } catch (e) {
      debugPrint('image attach failed: ${e.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось добавить изображение')),
      );
    }
  }

  void _insertManagedImage(
    String assetId,
    String alt, {
    required Object expectedNoteToken,
  }) {
    final controller = _controller;
    if (!mounted ||
        controller == null ||
        !identical(expectedNoteToken, _noteToken)) {
      return;
    }
    final selection = controller.selection;
    final index = selection.isValid
        ? selection.start
        : controller.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    controller.replaceText(
      index,
      length,
      BlockEmbed.image('asset://$assetId'),
      TextSelection.collapsed(offset: index + 1),
    );
    controller.formatText(
      index,
      1,
      Attribute<String>('alt', AttributeScope.embeds, alt),
    );
    controller.formatText(
      index,
      1,
      const Attribute<String>('display', AttributeScope.embeds, 'wide'),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final note = _latest;
    final controller = _controller;
    if (note == null || controller == null) return;
    final expectedNoteToken = _noteToken;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final image = await ref.read(clipboardImageReaderProvider).readImage();
      if (image != null) {
        final images = await ref.read(imagesServiceProvider.future);
        final asset = await images.attachImageBytes(
          note,
          image.bytes,
          extension: image.extension,
        );
        _insertManagedImage(
          asset.id,
          'Изображение из буфера',
          expectedNoteToken: expectedNoteToken,
        );
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (text == null || text.isEmpty || !mounted) return;
      final selection = controller.selection;
      final index = selection.isValid
          ? selection.start
          : controller.document.length - 1;
      final length = selection.isValid ? selection.end - selection.start : 0;
      controller.replaceText(
        index,
        length,
        text,
        TextSelection.collapsed(offset: index + text.length),
      );
    } on ImageAttachException catch (error) {
      messenger.showSnackBar(PotokSnackBar(content: Text(error.message)));
    } on ClipboardImageReadException catch (error) {
      messenger.showSnackBar(PotokSnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('clipboard image attach failed: ${error.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось вставить изображение')),
      );
    }
  }

  Future<void> _guarded(
    Future<void> Function(NotesService service) action, {
    String? failMessage,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await action(service);
    } on StateError {
      messenger.showSnackBar(
        PotokSnackBar(
          content: Text('Данные изменились — показана актуальная версия'),
        ),
      );
    } catch (e) {
      debugPrint('note action failed: ${e.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(
          content: Text(failMessage ?? 'Не удалось выполнить действие'),
        ),
      );
    }
  }

  Future<void> _moveToProject(Note note) async {
    final projects = ref.read(projectsProvider).value ?? const <Project>[];
    final c = PotokColors.of(context);
    final selected = await showDialog<_MoveTarget>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Перенести в проект'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(dialogContext).pop(const _MoveTarget(null)),
            child: Row(
              children: [
                Icon(Icons.crop_square_rounded, size: 14, color: c.muted),
                const SizedBox(width: 10),
                const Text('Без проекта'),
              ],
            ),
          ),
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_MoveTarget(project.id)),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 12, color: Color(project.colorArgb)),
                  const SizedBox(width: 10),
                  Flexible(child: Text(project.name)),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    if (!mounted) return;
    await moveNoteToProject(context, ref, note, selected.projectId);
  }

  Future<void> _moveToTrash(Note note) async {
    await _guarded(
      (service) => service.moveToTrash(note),
      failMessage: 'Не удалось удалить заметку',
    );
    if (!mounted) return;
    ref.read(selectedNoteIdProvider.notifier).select(null);
    if (widget.showBack && context.mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    _notesService = ref.watch(notesServiceProvider).value ?? _notesService;
    final note = ref.watch(selectedNoteProvider);
    _sync(note);

    if (note == null) {
      return Container(
        color: c.surface,
        alignment: Alignment.center,
        child: Text(
          'Выберите заметку',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }
    final controller = _controller!;

    return Container(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(
            note: note,
            status: _status,
            showBack: widget.showBack,
            onFavorite: () => _guarded(
              (service) => service.setFavorite(note, !note.isFavorite),
            ),
            onToggleDone: () => _guarded((service) => service.toggleDone(note)),
            onMove: () => _moveToProject(note),
            onTrash: () => _moveToTrash(note),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                _NoteTitleEditor(note: note),
                const SizedBox(height: 18),
                _ProjectRow(note: note),
                const SizedBox(height: 14),
                _TagsRow(note: note),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface2,
                    borderRadius: BorderRadius.circular(c.radiusSmall),
                    border: Border.all(color: c.line),
                  ),
                  child: QuillSimpleToolbar(
                    controller: controller,
                    config: QuillSimpleToolbarConfig(
                      decoration: const BoxDecoration(),
                      color: Colors.transparent,
                      sectionDividerColor: c.line,
                      showFontFamily: false,
                      showFontSize: false,
                      showUnderLineButton: false,
                      showInlineCode: false,
                      showColorButton: false,
                      showBackgroundColorButton: false,
                      showClearFormat: false,
                      showAlignmentButtons: false,
                      showHeaderStyle: false,
                      showListNumbers: false,
                      showListBullets: false,
                      showCodeBlock: false,
                      showQuote: false,
                      showIndent: false,
                      showSearchButton: false,
                      showSubscript: false,
                      showSuperscript: false,
                      customButtons: [
                        QuillToolbarCustomButtonOptions(
                          tooltip: 'Вставить изображение',
                          icon: const Icon(Icons.image_outlined),
                          onPressed: _insertImage,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                QuillEditor(
                  controller: controller,
                  focusNode: _editorFocus,
                  scrollController: _editorScroll,
                  config: QuillEditorConfig(
                    scrollable: false,
                    placeholder: 'Текст заметки…',
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    embedBuilders: const [_ManagedImageEmbedBuilder()],
                    customShortcuts: const {
                      SingleActivator(LogicalKeyboardKey.keyV, control: true):
                          PasteWithImagesIntent(),
                    },
                    customActions: {
                      PasteWithImagesIntent:
                          CallbackAction<PasteWithImagesIntent>(
                            onInvoke: (_) {
                              unawaited(_pasteFromClipboard());
                              return null;
                            },
                          ),
                    },
                  ),
                ),
                const SizedBox(height: 26),
                _AudioSection(
                  note: note,
                  onManualTranscription: _editorFocus.requestFocus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteTitleEditor extends ConsumerStatefulWidget {
  final Note note;

  const _NoteTitleEditor({required this.note});

  @override
  ConsumerState<_NoteTitleEditor> createState() => _NoteTitleEditorState();
}

class _NoteTitleEditorState extends ConsumerState<_NoteTitleEditor> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.note.title ?? '');
    _focus = FocusNode(debugLabel: 'note-title')
      ..addListener(() {
        if (!_focus.hasFocus) unawaited(_save());
      });
  }

  @override
  void didUpdateWidget(covariant _NoteTitleEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus &&
        (oldWidget.note.id != widget.note.id ||
            oldWidget.note.title != widget.note.title)) {
      _controller.text = widget.note.title ?? '';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final value = _controller.text.trim();
    if (value == (widget.note.title ?? '').trim()) return;
    _saving = true;
    try {
      await ref.read(noteFlushRegistryProvider).flushNow();
      final fresh = ref.read(selectedNoteProvider);
      if (fresh == null || fresh.id != widget.note.id) return;
      final service = await ref.read(notesServiceProvider.future);
      await service.updateTitle(fresh, value);
    } on StateError {
      final fresh = ref.read(selectedNoteProvider);
      if (fresh?.id == widget.note.id) {
        _controller.text = fresh?.title ?? '';
      }
    } catch (error) {
      debugPrint('title save failed: ${error.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          PotokSnackBar(content: const Text('Не удалось сохранить название')),
        );
      }
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return TextField(
      key: const ValueKey('note-title-editor'),
      controller: _controller,
      focusNode: _focus,
      maxLength: 120,
      maxLines: 2,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _save(),
      style: TextStyle(
        color: c.text,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        hintText: 'Название создастся из содержания',
        counterText: '',
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintStyle: TextStyle(color: c.muted, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _ManagedImageEmbedBuilder extends EmbedBuilder {
  const _ManagedImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data;
    final assetId = source is String && source.startsWith('asset://')
        ? source.substring('asset://'.length)
        : null;
    if (assetId == null ||
        assetId.isEmpty ||
        assetId.contains(RegExp(r'[/\\?#]'))) {
      return const _UnavailableImage();
    }
    final attributes = embedContext.node.style.attributes;
    final altValue = attributes['alt']?.value;
    final alt = altValue is String && altValue.trim().isNotEmpty
        ? altValue.trim()
        : 'Изображение в заметке';
    final displayValue = attributes['display']?.value;
    final compact = displayValue == 'compact';
    return Consumer(
      builder: (context, ref, _) {
        final file = ref.watch(imageAssetFileProvider(assetId));
        return file.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => const _UnavailableImage(),
          data: (imageFile) {
            if (imageFile == null) return const _UnavailableImage();
            Widget image = Semantics(
              label: alt,
              button: !embedContext.readOnly,
              hint: embedContext.readOnly
                  ? null
                  : 'Открыть свойства изображения',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  imageFile,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const _UnavailableImage(),
                ),
              ),
            );
            if (compact) {
              image = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: image,
              );
            }
            return Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: embedContext.readOnly
                    ? null
                    : () => _editImageProperties(
                        context,
                        embedContext,
                        initialAlt: alt,
                        initialDisplay: compact ? 'compact' : 'wide',
                      ),
                child: image,
              ),
            );
          },
        );
      },
    );
  }
}

Future<void> _editImageProperties(
  BuildContext context,
  EmbedContext embedContext, {
  required String initialAlt,
  required String initialDisplay,
}) async {
  final nodeOffset = embedContext.node.documentOffset;
  final altController = TextEditingController(text: initialAlt);
  var display = initialDisplay;
  try {
    final result = await showDialog<({String alt, String display})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Свойства изображения'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: altController,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Описание для доступности',
                  hintText: 'Что изображено',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'wide', label: Text('По ширине')),
                  ButtonSegment(value: 'compact', label: Text('Компактно')),
                ],
                selected: {display},
                onSelectionChanged: (selection) {
                  setState(() => display = selection.single);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop((alt: altController.text.trim(), display: display)),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null ||
        nodeOffset >= embedContext.controller.document.length) {
      return;
    }
    embedContext.controller.formatText(
      nodeOffset,
      1,
      Attribute<String>(
        'alt',
        AttributeScope.embeds,
        result.alt.isEmpty ? 'Изображение' : result.alt,
      ),
    );
    embedContext.controller.formatText(
      nodeOffset,
      1,
      Attribute<String>('display', AttributeScope.embeds, result.display),
    );
  } finally {
    altController.dispose();
  }
}

class _UnavailableImage extends StatelessWidget {
  const _UnavailableImage();

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(c.radiusSmall),
        border: Border.all(color: c.line),
      ),
      child: Text(
        'Изображение недоступно',
        style: TextStyle(fontSize: 12, color: c.muted),
      ),
    );
  }
}

class _MoveTarget {
  final String? projectId;
  const _MoveTarget(this.projectId);
}

class _Toolbar extends StatelessWidget {
  final Note note;
  final _SaveStatus status;
  final bool showBack;
  final VoidCallback onFavorite;
  final VoidCallback onToggleDone;
  final VoidCallback onMove;
  final VoidCallback onTrash;

  const _Toolbar({
    required this.note,
    required this.status,
    required this.showBack,
    required this.onFavorite,
    required this.onToggleDone,
    required this.onMove,
    required this.onTrash,
  });

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final done = note.status == NoteStatus.done;
    final (dotColor, label) = switch (status) {
      _SaveStatus.saved => (c.decision, 'Все изменения сохранены'),
      _SaveStatus.saving => (c.muted, 'Сохраняется…'),
      _SaveStatus.error => (c.danger, 'Ошибка сохранения'),
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Назад',
                icon: Icon(Icons.arrow_back_rounded, color: c.text),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          Expanded(
            child: Row(
              children: [
                Icon(Icons.circle, size: 8, color: dotColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: dotColor),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: note.isFavorite ? 'Убрать из избранного' : 'В избранное',
            icon: Icon(
              note.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: note.isFavorite ? c.accent : c.muted,
            ),
            onPressed: onFavorite,
          ),
          IconButton(
            tooltip: done ? 'Вернуть в работу' : 'Выполнено',
            icon: Icon(
              done ? Icons.check_circle_rounded : Icons.check_circle_outline,
              color: done ? c.decision : c.muted,
            ),
            onPressed: onToggleDone,
          ),
          PopupMenuButton<String>(
            tooltip: 'Другие действия',
            icon: Icon(Icons.more_horiz_rounded, color: c.muted),
            onSelected: (value) {
              if (value == 'move') onMove();
              if (value == 'trash') onTrash();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'move',
                child: Text('Перенести в проект…'),
              ),
              PopupMenuItem(
                value: 'trash',
                child: Text('В корзину', style: TextStyle(color: c.danger)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectRow extends ConsumerWidget {
  final Note note;
  const _ProjectRow({required this.note});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    Project? project;
    for (final p in projects) {
      if (p.id == note.projectId) {
        project = p;
        break;
      }
    }
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: project != null ? Color(project.colorArgb) : c.muted,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            project?.name ?? 'Без проекта',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
        ),
      ],
    );
  }
}

class _TagsRow extends ConsumerWidget {
  static const _createTagValue = '__create_tag__';
  final Note note;

  const _TagsRow({required this.note});

  Future<void> _runTagAction(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String failMessage,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on StateError {
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Тег недоступен для этой заметки')),
      );
    } catch (e) {
      debugPrint('tag action failed: ${e.runtimeType}');
      messenger.showSnackBar(PotokSnackBar(content: Text(failMessage)));
    }
  }

  Future<void> _createAndAssign(BuildContext context, WidgetRef ref) async {
    final tagId = await showTagEditorDialog(
      context,
      ref,
      initialProjectId: note.projectId,
    );
    if (tagId == null || !context.mounted) return;
    await _runTagAction(context, ref, () async {
      final service = await ref.read(tagsServiceProvider.future);
      await service.assignTag(note.id, tagId);
    }, 'Тег создан, но его не удалось добавить к заметке');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final noteTags =
        ref.watch(noteTagsProvider(note.id)).value ?? const <Tag>[];
    final available =
        ref.watch(availableTagsProvider(note.projectId)).value ?? const <Tag>[];
    final assignedIds = noteTags.map((t) => t.id).toSet();
    final addable = available
        .where((t) => !assignedIds.contains(t.id))
        .toList(growable: false);

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final tag in noteTags)
          Tooltip(
            message: 'Снять тег',
            waitDuration: const Duration(milliseconds: 600),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _runTagAction(context, ref, () async {
                final service = await ref.read(tagsServiceProvider.future);
                await service.unassignTag(note.id, tag.id);
              }, 'Не удалось снять тег'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Color(tag.colorArgb).withValues(alpha: 0.12),
                  border: Border.all(
                    color: Color(tag.colorArgb).withValues(alpha: 0.45),
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tag.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(tag.colorArgb),
                  ),
                ),
              ),
            ),
          ),
        PopupMenuButton<String>(
          tooltip: 'Добавить тег',
          onSelected: (tagId) {
            if (tagId == _createTagValue) {
              unawaited(_createAndAssign(context, ref));
              return;
            }
            unawaited(
              _runTagAction(context, ref, () async {
                final service = await ref.read(tagsServiceProvider.future);
                await service.assignTag(note.id, tagId);
              }, 'Не удалось добавить тег'),
            );
          },
          itemBuilder: (context) => [
            for (final tag in addable)
              PopupMenuItem(
                value: tag.id,
                child: Row(
                  children: [
                    Icon(Icons.circle, size: 10, color: Color(tag.colorArgb)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(tag.name)),
                  ],
                ),
              ),
            if (addable.isNotEmpty) const PopupMenuDivider(),
            const PopupMenuItem(
              value: _createTagValue,
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Создать тег…'),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '+ тег',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ),
        ),
      ],
    );
  }
}

/// Аудиоблок: исходная запись + постановка ASR в очередь + ревизии.
/// Прогресс job'а виден через состояния TranscriptRevision (очередь durable,
/// локального «идёт расшифровка» флага нет).
class _AudioSection extends ConsumerWidget {
  final Note note;
  final VoidCallback onManualTranscription;

  const _AudioSection({
    required this.note,
    required this.onManualTranscription,
  });

  Future<void> _enqueue(
    BuildContext context,
    WidgetRef ref,
    String assetId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.enqueue(note.id, assetId);
    } catch (e) {
      debugPrint('enqueue transcription failed: ${e.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(
          content: Text('Не удалось поставить расшифровку в очередь'),
        ),
      );
    }
  }

  Future<void> _retry(
    BuildContext context,
    WidgetRef ref,
    String revisionId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queue = await ref.read(transcriptionQueueProvider.future);
      await queue.retry(revisionId);
    } catch (e) {
      debugPrint('retry transcription failed: ${e.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось повторить расшифровку')),
      );
    }
  }

  Future<void> _accept(
    BuildContext context,
    WidgetRef ref,
    String revisionId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await service.acceptTranscript(note.id, revisionId);
    } on StateError {
      messenger.showSnackBar(
        PotokSnackBar(content: Text('Заметка изменилась — повторите принятие')),
      );
    } catch (e) {
      debugPrint('accept transcript failed: ${e.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось принять расшифровку')),
      );
    }
  }

  Future<void> _removeAudio(
    BuildContext context,
    WidgetRef ref,
    MediaAsset asset,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить аудио?'),
        content: const Text(
          'Запись перейдёт в корзину. Текст заметки и расшифровки не изменятся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('В корзину'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = await ref.read(notesServiceProvider.future);
      await service.moveAudioToTrash(note, asset);
    } catch (error) {
      debugPrint('audio trash failed: ${error.runtimeType}');
      messenger.showSnackBar(
        PotokSnackBar(content: const Text('Не удалось удалить аудио')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final assets =
        ref.watch(audioAssetsProvider(note.id)).value ?? const <MediaAsset>[];
    final revisions =
        ref.watch(revisionsProvider(note.id)).value ??
        const <TranscriptRevision>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.line, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Аудиовложения',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              TextButton.icon(
                key: const ValueKey('add-audio-attachment'),
                onPressed: () => showCaptureSheet(context, attachToNote: note),
                icon: const Icon(Icons.mic_none_rounded, size: 18),
                label: const Text('Добавить'),
              ),
            ],
          ),
          if (assets.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Записей пока нет',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          for (final asset in assets) ...[
            const SizedBox(height: 6),
            if (asset.lifecycleState == AssetLifecycle.missing)
              Semantics(
                liveRegion: true,
                child: Text(
                  'Аудиофайл отсутствует или повреждён',
                  style: TextStyle(color: c.danger, fontSize: 12),
                ),
              )
            else
              _AudioPlayerTile(
                asset: asset,
                onManualTranscription: onManualTranscription,
              ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${(asset.sizeBytes / 1024).ceil()} КБ · '
                    '${asset.mimeType == 'audio/mp4' ? 'M4A' : 'WAV'}',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
                if (asset.lifecycleState == AssetLifecycle.ready)
                  TextButton(
                    onPressed:
                        revisions.any(
                          (revision) =>
                              revision.audioAssetId == asset.id &&
                              (revision.state == TranscriptState.queued ||
                                  revision.state ==
                                      TranscriptState.recognizing),
                        )
                        ? null
                        : () => _enqueue(context, ref, asset.id),
                    child: const Text('Расшифровать'),
                  ),
                IconButton(
                  key: ValueKey('audio-delete-${asset.id}'),
                  tooltip: 'Удалить аудио',
                  onPressed: () => _removeAudio(context, ref, asset),
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                ),
              ],
            ),
            Divider(color: c.line),
          ],
          for (final revision in revisions)
            _RevisionTile(
              revision: revision,
              onAccept: (id) => _accept(context, ref, id),
              onRetry: (id) => _retry(context, ref, id),
              onConfigure: () => showAppearanceDialog(context, ref),
            ),
        ],
      ),
    );
  }
}

class _AudioPlayerTile extends ConsumerStatefulWidget {
  final MediaAsset asset;
  final VoidCallback onManualTranscription;

  const _AudioPlayerTile({
    required this.asset,
    required this.onManualTranscription,
  });

  @override
  ConsumerState<_AudioPlayerTile> createState() => _AudioPlayerTileState();
}

class _AudioPlayerTileState extends ConsumerState<_AudioPlayerTile> {
  late final AudioPlaybackController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(audioPlaybackControllerFactoryProvider)();
    _controller.addListener(_changed);
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final media = await ref.read(mediaStoreProvider.future);
      await _controller.open(media.absolutePath(widget.asset.relativePath));
    } catch (error) {
      debugPrint('audio player open failed: ${error.runtimeType}');
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final state = _controller.state;
    if (state.error != null) {
      return Semantics(
        liveRegion: true,
        child: Text(
          'Аудиофайл недоступен',
          style: TextStyle(color: c.danger, fontSize: 12),
        ),
      );
    }
    final maxMs = state.duration.inMilliseconds
        .toDouble()
        .clamp(1.0, double.infinity)
        .toDouble();
    final positionMs = state.position.inMilliseconds
        .toDouble()
        .clamp(0.0, maxMs)
        .toDouble();
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              key: ValueKey('audio-back-${widget.asset.id}'),
              tooltip: 'Назад на 10 секунд',
              onPressed: state.loading
                  ? null
                  : () => _controller.skip(const Duration(seconds: -10)),
              icon: const Icon(Icons.replay_10_rounded),
            ),
            IconButton.filled(
              key: ValueKey('audio-play-${widget.asset.id}'),
              tooltip: state.playing ? 'Пауза' : 'Воспроизвести',
              onPressed: state.loading ? null : _controller.toggle,
              icon: Icon(
                state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
            IconButton(
              key: ValueKey('audio-forward-${widget.asset.id}'),
              tooltip: 'Вперёд на 10 секунд',
              onPressed: state.loading
                  ? null
                  : () => _controller.skip(const Duration(seconds: 10)),
              icon: const Icon(Icons.forward_10_rounded),
            ),
            Expanded(
              child: Semantics(
                label: 'Позиция воспроизведения',
                value:
                    '${_durationLabel(state.position)} из '
                    '${_durationLabel(state.duration)}',
                child: Slider(
                  key: ValueKey('audio-progress-${widget.asset.id}'),
                  min: 0,
                  max: maxMs,
                  value: positionMs,
                  onChanged: state.loading
                      ? null
                      : (value) => _controller.seek(
                          Duration(milliseconds: value.round()),
                        ),
                ),
              ),
            ),
            PopupMenuButton<double>(
              key: ValueKey('audio-speed-${widget.asset.id}'),
              tooltip: 'Скорость воспроизведения',
              initialValue: state.speed,
              onSelected: _controller.setSpeed,
              itemBuilder: (_) => [
                for (final speed in JustAudioPlaybackController.supportedSpeeds)
                  PopupMenuItem(value: speed, child: Text('$speed×')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${state.speed}×',
                  style: TextStyle(color: c.text, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_durationLabel(state.position)} / ${_durationLabel(state.duration)}',
                style: TextStyle(color: c.muted, fontSize: 10),
              ),
            ),
            TextButton.icon(
              key: ValueKey('audio-manual-${widget.asset.id}'),
              onPressed: state.loading
                  ? null
                  : () async {
                      await _controller.pause();
                      widget.onManualTranscription();
                    },
              icon: const Icon(Icons.edit_note_rounded, size: 18),
              label: const Text('Печатать вручную'),
            ),
          ],
        ),
      ],
    );
  }
}

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _RevisionTile extends StatelessWidget {
  final TranscriptRevision revision;
  final Future<void> Function(String revisionId) onAccept;
  final Future<void> Function(String revisionId) onRetry;
  final VoidCallback onConfigure;

  const _RevisionTile({
    required this.revision,
    required this.onAccept,
    required this.onRetry,
    required this.onConfigure,
  });

  Widget _statusRow(
    PotokColors c,
    String label,
    Color labelColor, {
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: labelColor),
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    switch (revision.state) {
      case TranscriptState.ready:
        final accepted = revision.acceptedAtUtc != null;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(c.radiusSmall),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  revision.rawText.isEmpty ? '(пусто)' : revision.rawText,
                  style: TextStyle(fontSize: 12, color: c.text),
                ),
              ),
              if (accepted)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.check_rounded, size: 16, color: c.decision),
                )
              else
                TextButton(
                  onPressed: () => onAccept(revision.id),
                  child: const Text('Принять'),
                ),
            ],
          ),
        );
      case TranscriptState.recognizing:
      case TranscriptState.queued:
        return const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(minHeight: 2),
        );
      case TranscriptState.failed:
        return _statusRow(
          c,
          'Ошибка расшифровки',
          c.danger,
          action: TextButton(
            onPressed: () => onRetry(revision.id),
            child: const Text('Повторить'),
          ),
        );
      case TranscriptState.cancelled:
        return _statusRow(
          c,
          'Расшифровка отменена',
          c.muted,
          action: TextButton(
            onPressed: () => onRetry(revision.id),
            child: const Text('Повторить'),
          ),
        );
      case TranscriptState.waitingForModel:
        return _statusRow(
          c,
          'Модель не установлена',
          c.muted,
          action: TextButton(
            onPressed: onConfigure,
            child: const Text('Настроить'),
          ),
        );
    }
  }
}
