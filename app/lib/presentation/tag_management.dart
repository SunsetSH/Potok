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
}) async {
  const globalScope = '__global__';
  final controller = TextEditingController(text: tag?.name ?? '');
  var selectedColor = tag?.colorArgb ?? entityPresetColors.first;
  var scope = tag?.projectId ?? initialProjectId ?? globalScope;
  String? error;
  var submitting = false;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => Consumer(
      builder: (dialogContext, dialogRef, _) {
        final projects =
            dialogRef.watch(projectsProvider).value ?? const <Project>[];
        final c = PotokColors.of(dialogContext);
        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> submit() async {
              final name = controller.text.trim();
              if (name.isEmpty) {
                setState(() => error = 'Введите название тега');
                return;
              }
              setState(() {
                submitting = true;
                error = null;
              });
              try {
                final service = await dialogRef.read(
                  tagsServiceProvider.future,
                );
                final String id;
                if (tag == null) {
                  id = await service.createTag(
                    name: name,
                    colorArgb: selectedColor,
                    projectId: scope == globalScope ? null : scope,
                  );
                } else {
                  await service.updateTag(
                    tag,
                    name: name,
                    colorArgb: selectedColor,
                  );
                  id = tag.id;
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(id);
                }
              } on ArgumentError {
                if (dialogContext.mounted) {
                  setState(() {
                    submitting = false;
                    error = 'Название должно содержать от 1 до 60 символов';
                  });
                }
              } on StateError {
                if (dialogContext.mounted) {
                  setState(() {
                    submitting = false;
                    error = 'Такой тег уже есть или был изменён — повторите';
                  });
                }
              } catch (failure) {
                debugPrint('tag save failed: ${failure.runtimeType}');
                if (dialogContext.mounted) {
                  setState(() {
                    submitting = false;
                    error = 'Не удалось сохранить тег';
                  });
                }
              }
            }

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
                      controller: controller,
                      autofocus: true,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: 'Название',
                        errorText: error,
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: submitting ? null : (_) => submit(),
                    ),
                    const SizedBox(height: 12),
                    if (tag == null)
                      DropdownButtonFormField<String>(
                        key: const ValueKey('tag-scope'),
                        initialValue: scope,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Область действия',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: globalScope,
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
                        onChanged: submitting
                            ? null
                            : (value) {
                                if (value != null) {
                                  setState(() => scope = value);
                                }
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
                    Text(
                      'Цвет',
                      style: TextStyle(fontSize: 12, color: c.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final color in entityPresetColors)
                          Semantics(
                            label:
                                'Цвет тега ${entityPresetColors.indexOf(color) + 1}',
                            selected: color == selectedColor,
                            button: true,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: submitting
                                  ? null
                                  : () => setState(() => selectedColor = color),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Color(color),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: color == selectedColor
                                        ? c.text
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: color == selectedColor
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
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  key: const ValueKey('save-tag'),
                  onPressed: submitting ? null : submit,
                  child: const Text('Сохранить'),
                ),
              ],
            );
          },
        );
      },
    ),
  );
  // Keep the controller alive until the dialog exit animation detaches input.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
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
