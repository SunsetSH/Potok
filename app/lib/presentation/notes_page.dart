import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/notes_service.dart';
import '../domain/types.dart';
import '../infrastructure/db/database.dart';
import 'capture_sheet.dart';
import 'providers.dart';

class NotesPage extends ConsumerWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serviceAsync = ref.watch(notesServiceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Все заметки')),
      floatingActionButton: serviceAsync.maybeWhen(
        data: (service) => FloatingActionButton(
          tooltip: 'Создать заметку',
          onPressed: () => showCaptureSheet(context, service),
          child: const Icon(Icons.add),
        ),
        orElse: () => null,
      ),
      body: serviceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка запуска: $e')),
        data: (service) => _NotesList(service: service),
      ),
    );
  }
}

class _NotesList extends StatelessWidget {
  final NotesService service;
  const _NotesList({required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Note>>(
      stream: service.watchNotes(),
      builder: (context, snapshot) {
        final notes = snapshot.data;
        if (notes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (notes.isEmpty) {
          return const Center(
            child: Text('Пока пусто — создайте первую заметку'),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: notes.length,
          itemBuilder: (context, index) =>
              _NoteCard(note: notes[index], service: service),
        );
      },
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final NotesService service;
  const _NoteCard({required this.note, required this.service});

  @override
  Widget build(BuildContext context) {
    final done = note.status == NoteStatus.done;
    final preview = note.documentPlainText.isEmpty
        ? 'Аудиозаметка'
        : note.documentPlainText;
    return Opacity(
      opacity: done ? 0.58 : 1,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: done ? 'Вернуть в работу' : 'Выполнено',
                    icon: Icon(
                      done ? Icons.replay : Icons.check_circle_outline,
                    ),
                    onPressed: () => service.toggleDone(note),
                  ),
                ],
              ),
              if (note.sourceKind == SourceKind.audio)
                _AudioSection(note: note, service: service),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioSection extends StatefulWidget {
  final Note note;
  final NotesService service;
  const _AudioSection({required this.note, required this.service});

  @override
  State<_AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<_AudioSection> {
  bool _transcribing = false;

  Future<void> _transcribe(String assetId) async {
    setState(() => _transcribing = true);
    try {
      await widget.service.transcribe(widget.note.id, assetId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Расшифровка не удалась: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaAsset?>(
      stream: widget.service.watchReadyAudioAsset(widget.note.id),
      builder: (context, assetSnapshot) {
        final asset = assetSnapshot.data;
        if (asset == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, size: 16),
                const SizedBox(width: 6),
                Text('${(asset.sizeBytes / 1024).ceil()} КБ · WAV',
                    style: Theme.of(context).textTheme.bodySmall),
                const Spacer(),
                if (_transcribing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  TextButton(
                    onPressed: () => _transcribe(asset.id),
                    child: const Text('Расшифровать'),
                  ),
              ],
            ),
            _RevisionsSection(note: widget.note, service: widget.service),
          ],
        );
      },
    );
  }
}

class _RevisionsSection extends StatelessWidget {
  final Note note;
  final NotesService service;
  const _RevisionsSection({required this.note, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TranscriptRevision>>(
      stream: service.watchRevisions(note.id),
      builder: (context, snapshot) {
        final revisions = snapshot.data ?? const [];
        return Column(
          children: [
            for (final revision in revisions)
              _RevisionTile(note: note, revision: revision, service: service),
          ],
        );
      },
    );
  }
}

class _RevisionTile extends StatelessWidget {
  final Note note;
  final TranscriptRevision revision;
  final NotesService service;
  const _RevisionTile({
    required this.note,
    required this.revision,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (revision.state) {
      case TranscriptState.ready:
        final accepted = revision.acceptedAtUtc != null;
        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  revision.rawText.isEmpty ? '(пусто)' : revision.rawText,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (accepted)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.check, size: 16),
                )
              else
                TextButton(
                  onPressed: () async {
                    try {
                      await service.acceptTranscript(note.id, revision.id);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Не принято: $e')),
                        );
                      }
                    }
                  },
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
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Ошибка расшифровки',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        );
      case TranscriptState.waitingForModel:
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Модель не установлена',
              style: theme.textTheme.bodySmall),
        );
      case TranscriptState.cancelled:
        return const SizedBox.shrink();
    }
  }
}
