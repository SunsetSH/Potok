import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'entity_color_palette.dart';
import 'providers.dart';
import 'theme.dart';

/// Creates or edits a tag. Existing scope is immutable by design; creation
/// allows a global scope or one concrete project.
Future<String?> showTagEditorDialog(
  BuildContext context,
  WidgetRef ref, {
  Tag? tag,
  String? initialProjectId,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) =>
        _TagEditorDialog(tag: tag, initialProjectId: initialProjectId),
  );
}

const _tagEditorGlobalScope = '__global__';

/// Owns the name controller as widget state so it is only disposed once the
/// dialog Element itself is unmounted — tying disposal to an async future's
/// completion race with the dialog's own close animation.
class _TagEditorDialog extends ConsumerStatefulWidget {
  final Tag? tag;
  final String? initialProjectId;

  const _TagEditorDialog({this.tag, this.initialProjectId});

  @override
  ConsumerState<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends ConsumerState<_TagEditorDialog> {
  late final TextEditingController _nameController;
  late int _selectedColor;
  late String _scope;
  String? _error;
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.tag?.name ?? '');
    _selectedColor = widget.tag?.colorArgb ?? entityPresetColors.first;
    _scope =
        widget.tag?.projectId ??
        widget.initialProjectId ??
        _tagEditorGlobalScope;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tag = widget.tag;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите название тега');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final service = await ref.read(tagsServiceProvider.future);
      final String id;
      if (tag == null) {
        id = await service.createTag(
          name: name,
          colorArgb: _selectedColor,
          projectId: _scope == _tagEditorGlobalScope ? null : _scope,
        );
      } else {
        await service.updateTag(tag, name: name, colorArgb: _selectedColor);
        id = tag.id;
      }
      if (mounted) Navigator.of(context).pop(id);
    } on ArgumentError {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Название должно содержать от 1 до 60 символов';
        });
      }
    } on StateError {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Такой тег уже есть или был изменён — повторите';
        });
      }
    } catch (failure) {
      debugPrint('tag save failed: ${failure.runtimeType}');
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = 'Не удалось сохранить тег';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tag = widget.tag;
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final c = PotokColors.of(context);
    return AlertDialog(
      title: Text(tag == null ? 'Новый тег' : 'Редактировать тег'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('tag-name'),
              controller: _nameController,
              autofocus: true,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Название',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: _submitting ? null : (_) => _submit(),
            ),
            const SizedBox(height: 12),
            if (tag == null)
              DropdownButtonFormField<String>(
                key: const ValueKey('tag-scope'),
                initialValue: _scope,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Область действия',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: _tagEditorGlobalScope,
                    child: Text('Глобальный · все заметки'),
                  ),
                  for (final project in projects)
                    DropdownMenuItem(
                      value: project.id,
                      child: Text(
                        'Проект · ${project.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value != null) setState(() => _scope = value);
                      },
              )
            else
              Text(
                tag.scope == TagScope.global
                    ? 'Глобальный тег'
                    : 'Тег проекта · область не изменяется',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            const SizedBox(height: 14),
            Text('Цвет', style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in entityPresetColors)
                  Semantics(
                    label:
                        'Цвет тега ${entityPresetColors.indexOf(color) + 1}',
                    selected: color == _selectedColor,
                    button: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _submitting
                          ? null
                          : () => setState(() => _selectedColor = color),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == _selectedColor
                                ? c.text
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: color == _selectedColor
                            ? const Icon(
                                Icons.check_rounded,
                                size: 17,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('save-tag'),
          onPressed: _submitting ? null : _submit,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class TagManagementSection extends ConsumerWidget {
  const TagManagementSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PotokColors.of(context);
    final projects = ref.watch(projectsProvider).value ?? const <Project>[];
    final tags = ref.watch(allTagsProvider);
    String scopeLabel(Tag tag) {
      if (tag.projectId == null) return 'Глобальный';
      for (final project in projects) {
        if (project.id == tag.projectId) return 'Проект · ${project.name}';
      }
      return 'Проект недоступен';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('create-custom-tag'),
          onPressed: () => showTagEditorDialog(context, ref),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Создать тег'),
        ),
        const SizedBox(height: 8),
        tags.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (_, _) => const Text('Не удалось загрузить теги'),
          data: (items) => Column(
            children: [
              for (final tag in items)
                ListTile(
                  key: ValueKey('manage-tag-${tag.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    Icons.label_rounded,
                    color: Color(tag.colorArgb),
                  ),
                  title: Text(tag.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    scopeLabel(tag),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                  trailing: IconButton(
                    tooltip: 'Редактировать тег',
                    onPressed: () =>
                        showTagEditorDialog(context, ref, tag: tag),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
