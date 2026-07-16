// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $NotesTable extends Notes with TableInfo<$NotesTable, Note> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<NoteStatus, String> status =
      GeneratedColumn<String>(
        'status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('in_work'),
      ).withConverter<NoteStatus>($NotesTable.$converterstatus);
  static const VerificationMeta _documentJsonMeta = const VerificationMeta(
    'documentJson',
  );
  @override
  late final GeneratedColumn<String> documentJson = GeneratedColumn<String>(
    'document_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _documentPlainTextMeta = const VerificationMeta(
    'documentPlainText',
  );
  @override
  late final GeneratedColumn<String> documentPlainText =
      GeneratedColumn<String>(
        'document_plain_text',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  @override
  late final GeneratedColumnWithTypeConverter<SourceKind, String> sourceKind =
      GeneratedColumn<String>(
        'source_kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<SourceKind>($NotesTable.$convertersourceKind);
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _favoritedAtUtcMeta = const VerificationMeta(
    'favoritedAtUtc',
  );
  @override
  late final GeneratedColumn<int> favoritedAtUtc = GeneratedColumn<int>(
    'favorited_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtUtcMeta = const VerificationMeta(
    'completedAtUtc',
  );
  @override
  late final GeneratedColumn<int> completedAtUtc = GeneratedColumn<int>(
    'completed_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventAtUtcMeta = const VerificationMeta(
    'eventAtUtc',
  );
  @override
  late final GeneratedColumn<int> eventAtUtc = GeneratedColumn<int>(
    'event_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtUtcMeta = const VerificationMeta(
    'deletedAtUtc',
  );
  @override
  late final GeneratedColumn<int> deletedAtUtc = GeneratedColumn<int>(
    'deleted_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    projectId,
    title,
    status,
    documentJson,
    documentPlainText,
    sourceKind,
    isPinned,
    isFavorite,
    favoritedAtUtc,
    completedAtUtc,
    eventAtUtc,
    createdAtUtc,
    updatedAtUtc,
    deletedAtUtc,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Note> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('document_json')) {
      context.handle(
        _documentJsonMeta,
        documentJson.isAcceptableOrUnknown(
          data['document_json']!,
          _documentJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentJsonMeta);
    }
    if (data.containsKey('document_plain_text')) {
      context.handle(
        _documentPlainTextMeta,
        documentPlainText.isAcceptableOrUnknown(
          data['document_plain_text']!,
          _documentPlainTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_documentPlainTextMeta);
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('favorited_at_utc')) {
      context.handle(
        _favoritedAtUtcMeta,
        favoritedAtUtc.isAcceptableOrUnknown(
          data['favorited_at_utc']!,
          _favoritedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('completed_at_utc')) {
      context.handle(
        _completedAtUtcMeta,
        completedAtUtc.isAcceptableOrUnknown(
          data['completed_at_utc']!,
          _completedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('event_at_utc')) {
      context.handle(
        _eventAtUtcMeta,
        eventAtUtc.isAcceptableOrUnknown(
          data['event_at_utc']!,
          _eventAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('deleted_at_utc')) {
      context.handle(
        _deletedAtUtcMeta,
        deletedAtUtc.isAcceptableOrUnknown(
          data['deleted_at_utc']!,
          _deletedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Note map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Note(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      status: $NotesTable.$converterstatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}status'],
        )!,
      ),
      documentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_json'],
      )!,
      documentPlainText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_plain_text'],
      )!,
      sourceKind: $NotesTable.$convertersourceKind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source_kind'],
        )!,
      ),
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      favoritedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}favorited_at_utc'],
      ),
      completedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completed_at_utc'],
      ),
      eventAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}event_at_utc'],
      ),
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      deletedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_utc'],
      ),
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
    );
  }

  @override
  $NotesTable createAlias(String alias) {
    return $NotesTable(attachedDatabase, alias);
  }

  static TypeConverter<NoteStatus, String> $converterstatus =
      const _NoteStatusConverter();
  static JsonTypeConverter2<SourceKind, String, String> $convertersourceKind =
      const EnumNameConverter<SourceKind>(SourceKind.values);
}

class Note extends DataClass implements Insertable<Note> {
  final String id;
  final String? projectId;
  final String? title;
  final NoteStatus status;
  final String documentJson;
  final String documentPlainText;
  final SourceKind sourceKind;
  final bool isPinned;
  final bool isFavorite;
  final int? favoritedAtUtc;
  final int? completedAtUtc;
  final int? eventAtUtc;
  final int createdAtUtc;
  final int updatedAtUtc;
  final int? deletedAtUtc;
  final int revision;
  const Note({
    required this.id,
    this.projectId,
    this.title,
    required this.status,
    required this.documentJson,
    required this.documentPlainText,
    required this.sourceKind,
    required this.isPinned,
    required this.isFavorite,
    this.favoritedAtUtc,
    this.completedAtUtc,
    this.eventAtUtc,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.deletedAtUtc,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    {
      map['status'] = Variable<String>(
        $NotesTable.$converterstatus.toSql(status),
      );
    }
    map['document_json'] = Variable<String>(documentJson);
    map['document_plain_text'] = Variable<String>(documentPlainText);
    {
      map['source_kind'] = Variable<String>(
        $NotesTable.$convertersourceKind.toSql(sourceKind),
      );
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || favoritedAtUtc != null) {
      map['favorited_at_utc'] = Variable<int>(favoritedAtUtc);
    }
    if (!nullToAbsent || completedAtUtc != null) {
      map['completed_at_utc'] = Variable<int>(completedAtUtc);
    }
    if (!nullToAbsent || eventAtUtc != null) {
      map['event_at_utc'] = Variable<int>(eventAtUtc);
    }
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    if (!nullToAbsent || deletedAtUtc != null) {
      map['deleted_at_utc'] = Variable<int>(deletedAtUtc);
    }
    map['revision'] = Variable<int>(revision);
    return map;
  }

  NotesCompanion toCompanion(bool nullToAbsent) {
    return NotesCompanion(
      id: Value(id),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      status: Value(status),
      documentJson: Value(documentJson),
      documentPlainText: Value(documentPlainText),
      sourceKind: Value(sourceKind),
      isPinned: Value(isPinned),
      isFavorite: Value(isFavorite),
      favoritedAtUtc: favoritedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(favoritedAtUtc),
      completedAtUtc: completedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtc),
      eventAtUtc: eventAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(eventAtUtc),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      deletedAtUtc: deletedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAtUtc),
      revision: Value(revision),
    );
  }

  factory Note.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Note(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String?>(json['projectId']),
      title: serializer.fromJson<String?>(json['title']),
      status: serializer.fromJson<NoteStatus>(json['status']),
      documentJson: serializer.fromJson<String>(json['documentJson']),
      documentPlainText: serializer.fromJson<String>(json['documentPlainText']),
      sourceKind: $NotesTable.$convertersourceKind.fromJson(
        serializer.fromJson<String>(json['sourceKind']),
      ),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      favoritedAtUtc: serializer.fromJson<int?>(json['favoritedAtUtc']),
      completedAtUtc: serializer.fromJson<int?>(json['completedAtUtc']),
      eventAtUtc: serializer.fromJson<int?>(json['eventAtUtc']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      deletedAtUtc: serializer.fromJson<int?>(json['deletedAtUtc']),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String?>(projectId),
      'title': serializer.toJson<String?>(title),
      'status': serializer.toJson<NoteStatus>(status),
      'documentJson': serializer.toJson<String>(documentJson),
      'documentPlainText': serializer.toJson<String>(documentPlainText),
      'sourceKind': serializer.toJson<String>(
        $NotesTable.$convertersourceKind.toJson(sourceKind),
      ),
      'isPinned': serializer.toJson<bool>(isPinned),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'favoritedAtUtc': serializer.toJson<int?>(favoritedAtUtc),
      'completedAtUtc': serializer.toJson<int?>(completedAtUtc),
      'eventAtUtc': serializer.toJson<int?>(eventAtUtc),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'deletedAtUtc': serializer.toJson<int?>(deletedAtUtc),
      'revision': serializer.toJson<int>(revision),
    };
  }

  Note copyWith({
    String? id,
    Value<String?> projectId = const Value.absent(),
    Value<String?> title = const Value.absent(),
    NoteStatus? status,
    String? documentJson,
    String? documentPlainText,
    SourceKind? sourceKind,
    bool? isPinned,
    bool? isFavorite,
    Value<int?> favoritedAtUtc = const Value.absent(),
    Value<int?> completedAtUtc = const Value.absent(),
    Value<int?> eventAtUtc = const Value.absent(),
    int? createdAtUtc,
    int? updatedAtUtc,
    Value<int?> deletedAtUtc = const Value.absent(),
    int? revision,
  }) => Note(
    id: id ?? this.id,
    projectId: projectId.present ? projectId.value : this.projectId,
    title: title.present ? title.value : this.title,
    status: status ?? this.status,
    documentJson: documentJson ?? this.documentJson,
    documentPlainText: documentPlainText ?? this.documentPlainText,
    sourceKind: sourceKind ?? this.sourceKind,
    isPinned: isPinned ?? this.isPinned,
    isFavorite: isFavorite ?? this.isFavorite,
    favoritedAtUtc: favoritedAtUtc.present
        ? favoritedAtUtc.value
        : this.favoritedAtUtc,
    completedAtUtc: completedAtUtc.present
        ? completedAtUtc.value
        : this.completedAtUtc,
    eventAtUtc: eventAtUtc.present ? eventAtUtc.value : this.eventAtUtc,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    deletedAtUtc: deletedAtUtc.present ? deletedAtUtc.value : this.deletedAtUtc,
    revision: revision ?? this.revision,
  );
  Note copyWithCompanion(NotesCompanion data) {
    return Note(
      id: data.id.present ? data.id.value : this.id,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      title: data.title.present ? data.title.value : this.title,
      status: data.status.present ? data.status.value : this.status,
      documentJson: data.documentJson.present
          ? data.documentJson.value
          : this.documentJson,
      documentPlainText: data.documentPlainText.present
          ? data.documentPlainText.value
          : this.documentPlainText,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      favoritedAtUtc: data.favoritedAtUtc.present
          ? data.favoritedAtUtc.value
          : this.favoritedAtUtc,
      completedAtUtc: data.completedAtUtc.present
          ? data.completedAtUtc.value
          : this.completedAtUtc,
      eventAtUtc: data.eventAtUtc.present
          ? data.eventAtUtc.value
          : this.eventAtUtc,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      deletedAtUtc: data.deletedAtUtc.present
          ? data.deletedAtUtc.value
          : this.deletedAtUtc,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Note(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('documentJson: $documentJson, ')
          ..write('documentPlainText: $documentPlainText, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('isPinned: $isPinned, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('favoritedAtUtc: $favoritedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('eventAtUtc: $eventAtUtc, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('deletedAtUtc: $deletedAtUtc, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    projectId,
    title,
    status,
    documentJson,
    documentPlainText,
    sourceKind,
    isPinned,
    isFavorite,
    favoritedAtUtc,
    completedAtUtc,
    eventAtUtc,
    createdAtUtc,
    updatedAtUtc,
    deletedAtUtc,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Note &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.title == this.title &&
          other.status == this.status &&
          other.documentJson == this.documentJson &&
          other.documentPlainText == this.documentPlainText &&
          other.sourceKind == this.sourceKind &&
          other.isPinned == this.isPinned &&
          other.isFavorite == this.isFavorite &&
          other.favoritedAtUtc == this.favoritedAtUtc &&
          other.completedAtUtc == this.completedAtUtc &&
          other.eventAtUtc == this.eventAtUtc &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.deletedAtUtc == this.deletedAtUtc &&
          other.revision == this.revision);
}

class NotesCompanion extends UpdateCompanion<Note> {
  final Value<String> id;
  final Value<String?> projectId;
  final Value<String?> title;
  final Value<NoteStatus> status;
  final Value<String> documentJson;
  final Value<String> documentPlainText;
  final Value<SourceKind> sourceKind;
  final Value<bool> isPinned;
  final Value<bool> isFavorite;
  final Value<int?> favoritedAtUtc;
  final Value<int?> completedAtUtc;
  final Value<int?> eventAtUtc;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<int?> deletedAtUtc;
  final Value<int> revision;
  final Value<int> rowid;
  const NotesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    this.documentJson = const Value.absent(),
    this.documentPlainText = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.favoritedAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.eventAtUtc = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.deletedAtUtc = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NotesCompanion.insert({
    required String id,
    this.projectId = const Value.absent(),
    this.title = const Value.absent(),
    this.status = const Value.absent(),
    required String documentJson,
    required String documentPlainText,
    required SourceKind sourceKind,
    this.isPinned = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.favoritedAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.eventAtUtc = const Value.absent(),
    required int createdAtUtc,
    required int updatedAtUtc,
    this.deletedAtUtc = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       documentJson = Value(documentJson),
       documentPlainText = Value(documentPlainText),
       sourceKind = Value(sourceKind),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<Note> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? title,
    Expression<String>? status,
    Expression<String>? documentJson,
    Expression<String>? documentPlainText,
    Expression<String>? sourceKind,
    Expression<bool>? isPinned,
    Expression<bool>? isFavorite,
    Expression<int>? favoritedAtUtc,
    Expression<int>? completedAtUtc,
    Expression<int>? eventAtUtc,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<int>? deletedAtUtc,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (title != null) 'title': title,
      if (status != null) 'status': status,
      if (documentJson != null) 'document_json': documentJson,
      if (documentPlainText != null) 'document_plain_text': documentPlainText,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (isPinned != null) 'is_pinned': isPinned,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (favoritedAtUtc != null) 'favorited_at_utc': favoritedAtUtc,
      if (completedAtUtc != null) 'completed_at_utc': completedAtUtc,
      if (eventAtUtc != null) 'event_at_utc': eventAtUtc,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (deletedAtUtc != null) 'deleted_at_utc': deletedAtUtc,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NotesCompanion copyWith({
    Value<String>? id,
    Value<String?>? projectId,
    Value<String?>? title,
    Value<NoteStatus>? status,
    Value<String>? documentJson,
    Value<String>? documentPlainText,
    Value<SourceKind>? sourceKind,
    Value<bool>? isPinned,
    Value<bool>? isFavorite,
    Value<int?>? favoritedAtUtc,
    Value<int?>? completedAtUtc,
    Value<int?>? eventAtUtc,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<int?>? deletedAtUtc,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return NotesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      status: status ?? this.status,
      documentJson: documentJson ?? this.documentJson,
      documentPlainText: documentPlainText ?? this.documentPlainText,
      sourceKind: sourceKind ?? this.sourceKind,
      isPinned: isPinned ?? this.isPinned,
      isFavorite: isFavorite ?? this.isFavorite,
      favoritedAtUtc: favoritedAtUtc ?? this.favoritedAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      eventAtUtc: eventAtUtc ?? this.eventAtUtc,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(
        $NotesTable.$converterstatus.toSql(status.value),
      );
    }
    if (documentJson.present) {
      map['document_json'] = Variable<String>(documentJson.value);
    }
    if (documentPlainText.present) {
      map['document_plain_text'] = Variable<String>(documentPlainText.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(
        $NotesTable.$convertersourceKind.toSql(sourceKind.value),
      );
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (favoritedAtUtc.present) {
      map['favorited_at_utc'] = Variable<int>(favoritedAtUtc.value);
    }
    if (completedAtUtc.present) {
      map['completed_at_utc'] = Variable<int>(completedAtUtc.value);
    }
    if (eventAtUtc.present) {
      map['event_at_utc'] = Variable<int>(eventAtUtc.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (deletedAtUtc.present) {
      map['deleted_at_utc'] = Variable<int>(deletedAtUtc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NotesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('title: $title, ')
          ..write('status: $status, ')
          ..write('documentJson: $documentJson, ')
          ..write('documentPlainText: $documentPlainText, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('isPinned: $isPinned, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('favoritedAtUtc: $favoritedAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('eventAtUtc: $eventAtUtc, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('deletedAtUtc: $deletedAtUtc, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaAssetsTable extends MediaAssets
    with TableInfo<$MediaAssetsTable, MediaAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaAssetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerNoteIdMeta = const VerificationMeta(
    'ownerNoteId',
  );
  @override
  late final GeneratedColumn<String> ownerNoteId = GeneratedColumn<String>(
    'owner_note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<AssetKind, String> kind =
      GeneratedColumn<String>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<AssetKind>($MediaAssetsTable.$converterkind);
  static const VerificationMeta _relativePathMeta = const VerificationMeta(
    'relativePath',
  );
  @override
  late final GeneratedColumn<String> relativePath = GeneratedColumn<String>(
    'relative_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<AssetLifecycle, String>
  lifecycleState = GeneratedColumn<String>(
    'lifecycle_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<AssetLifecycle>($MediaAssetsTable.$converterlifecycleState);
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<int> updatedAtUtc = GeneratedColumn<int>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtUtcMeta = const VerificationMeta(
    'deletedAtUtc',
  );
  @override
  late final GeneratedColumn<int> deletedAtUtc = GeneratedColumn<int>(
    'deleted_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    ownerNoteId,
    kind,
    relativePath,
    mimeType,
    sizeBytes,
    sha256,
    lifecycleState,
    createdAtUtc,
    updatedAtUtc,
    deletedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('owner_note_id')) {
      context.handle(
        _ownerNoteIdMeta,
        ownerNoteId.isAcceptableOrUnknown(
          data['owner_note_id']!,
          _ownerNoteIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_ownerNoteIdMeta);
    }
    if (data.containsKey('relative_path')) {
      context.handle(
        _relativePathMeta,
        relativePath.isAcceptableOrUnknown(
          data['relative_path']!,
          _relativePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_relativePathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('deleted_at_utc')) {
      context.handle(
        _deletedAtUtcMeta,
        deletedAtUtc.isAcceptableOrUnknown(
          data['deleted_at_utc']!,
          _deletedAtUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ownerNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_note_id'],
      )!,
      kind: $MediaAssetsTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}kind'],
        )!,
      ),
      relativePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relative_path'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      ),
      lifecycleState: $MediaAssetsTable.$converterlifecycleState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}lifecycle_state'],
        )!,
      ),
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      deletedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at_utc'],
      ),
    );
  }

  @override
  $MediaAssetsTable createAlias(String alias) {
    return $MediaAssetsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<AssetKind, String, String> $converterkind =
      const EnumNameConverter<AssetKind>(AssetKind.values);
  static JsonTypeConverter2<AssetLifecycle, String, String>
  $converterlifecycleState = const EnumNameConverter<AssetLifecycle>(
    AssetLifecycle.values,
  );
}

class MediaAsset extends DataClass implements Insertable<MediaAsset> {
  final String id;
  final String ownerNoteId;
  final AssetKind kind;
  final String relativePath;
  final String mimeType;
  final int sizeBytes;
  final String? sha256;
  final AssetLifecycle lifecycleState;
  final int createdAtUtc;
  final int updatedAtUtc;
  final int? deletedAtUtc;
  const MediaAsset({
    required this.id,
    required this.ownerNoteId,
    required this.kind,
    required this.relativePath,
    required this.mimeType,
    required this.sizeBytes,
    this.sha256,
    required this.lifecycleState,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.deletedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['owner_note_id'] = Variable<String>(ownerNoteId);
    {
      map['kind'] = Variable<String>(
        $MediaAssetsTable.$converterkind.toSql(kind),
      );
    }
    map['relative_path'] = Variable<String>(relativePath);
    map['mime_type'] = Variable<String>(mimeType);
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || sha256 != null) {
      map['sha256'] = Variable<String>(sha256);
    }
    {
      map['lifecycle_state'] = Variable<String>(
        $MediaAssetsTable.$converterlifecycleState.toSql(lifecycleState),
      );
    }
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    map['updated_at_utc'] = Variable<int>(updatedAtUtc);
    if (!nullToAbsent || deletedAtUtc != null) {
      map['deleted_at_utc'] = Variable<int>(deletedAtUtc);
    }
    return map;
  }

  MediaAssetsCompanion toCompanion(bool nullToAbsent) {
    return MediaAssetsCompanion(
      id: Value(id),
      ownerNoteId: Value(ownerNoteId),
      kind: Value(kind),
      relativePath: Value(relativePath),
      mimeType: Value(mimeType),
      sizeBytes: Value(sizeBytes),
      sha256: sha256 == null && nullToAbsent
          ? const Value.absent()
          : Value(sha256),
      lifecycleState: Value(lifecycleState),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      deletedAtUtc: deletedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAtUtc),
    );
  }

  factory MediaAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaAsset(
      id: serializer.fromJson<String>(json['id']),
      ownerNoteId: serializer.fromJson<String>(json['ownerNoteId']),
      kind: $MediaAssetsTable.$converterkind.fromJson(
        serializer.fromJson<String>(json['kind']),
      ),
      relativePath: serializer.fromJson<String>(json['relativePath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      sha256: serializer.fromJson<String?>(json['sha256']),
      lifecycleState: $MediaAssetsTable.$converterlifecycleState.fromJson(
        serializer.fromJson<String>(json['lifecycleState']),
      ),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<int>(json['updatedAtUtc']),
      deletedAtUtc: serializer.fromJson<int?>(json['deletedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'ownerNoteId': serializer.toJson<String>(ownerNoteId),
      'kind': serializer.toJson<String>(
        $MediaAssetsTable.$converterkind.toJson(kind),
      ),
      'relativePath': serializer.toJson<String>(relativePath),
      'mimeType': serializer.toJson<String>(mimeType),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'sha256': serializer.toJson<String?>(sha256),
      'lifecycleState': serializer.toJson<String>(
        $MediaAssetsTable.$converterlifecycleState.toJson(lifecycleState),
      ),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<int>(updatedAtUtc),
      'deletedAtUtc': serializer.toJson<int?>(deletedAtUtc),
    };
  }

  MediaAsset copyWith({
    String? id,
    String? ownerNoteId,
    AssetKind? kind,
    String? relativePath,
    String? mimeType,
    int? sizeBytes,
    Value<String?> sha256 = const Value.absent(),
    AssetLifecycle? lifecycleState,
    int? createdAtUtc,
    int? updatedAtUtc,
    Value<int?> deletedAtUtc = const Value.absent(),
  }) => MediaAsset(
    id: id ?? this.id,
    ownerNoteId: ownerNoteId ?? this.ownerNoteId,
    kind: kind ?? this.kind,
    relativePath: relativePath ?? this.relativePath,
    mimeType: mimeType ?? this.mimeType,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256.present ? sha256.value : this.sha256,
    lifecycleState: lifecycleState ?? this.lifecycleState,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    deletedAtUtc: deletedAtUtc.present ? deletedAtUtc.value : this.deletedAtUtc,
  );
  MediaAsset copyWithCompanion(MediaAssetsCompanion data) {
    return MediaAsset(
      id: data.id.present ? data.id.value : this.id,
      ownerNoteId: data.ownerNoteId.present
          ? data.ownerNoteId.value
          : this.ownerNoteId,
      kind: data.kind.present ? data.kind.value : this.kind,
      relativePath: data.relativePath.present
          ? data.relativePath.value
          : this.relativePath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      lifecycleState: data.lifecycleState.present
          ? data.lifecycleState.value
          : this.lifecycleState,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      deletedAtUtc: data.deletedAtUtc.present
          ? data.deletedAtUtc.value
          : this.deletedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaAsset(')
          ..write('id: $id, ')
          ..write('ownerNoteId: $ownerNoteId, ')
          ..write('kind: $kind, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('lifecycleState: $lifecycleState, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('deletedAtUtc: $deletedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    ownerNoteId,
    kind,
    relativePath,
    mimeType,
    sizeBytes,
    sha256,
    lifecycleState,
    createdAtUtc,
    updatedAtUtc,
    deletedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaAsset &&
          other.id == this.id &&
          other.ownerNoteId == this.ownerNoteId &&
          other.kind == this.kind &&
          other.relativePath == this.relativePath &&
          other.mimeType == this.mimeType &&
          other.sizeBytes == this.sizeBytes &&
          other.sha256 == this.sha256 &&
          other.lifecycleState == this.lifecycleState &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.deletedAtUtc == this.deletedAtUtc);
}

class MediaAssetsCompanion extends UpdateCompanion<MediaAsset> {
  final Value<String> id;
  final Value<String> ownerNoteId;
  final Value<AssetKind> kind;
  final Value<String> relativePath;
  final Value<String> mimeType;
  final Value<int> sizeBytes;
  final Value<String?> sha256;
  final Value<AssetLifecycle> lifecycleState;
  final Value<int> createdAtUtc;
  final Value<int> updatedAtUtc;
  final Value<int?> deletedAtUtc;
  final Value<int> rowid;
  const MediaAssetsCompanion({
    this.id = const Value.absent(),
    this.ownerNoteId = const Value.absent(),
    this.kind = const Value.absent(),
    this.relativePath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.lifecycleState = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.deletedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaAssetsCompanion.insert({
    required String id,
    required String ownerNoteId,
    required AssetKind kind,
    required String relativePath,
    required String mimeType,
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    required AssetLifecycle lifecycleState,
    required int createdAtUtc,
    required int updatedAtUtc,
    this.deletedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       ownerNoteId = Value(ownerNoteId),
       kind = Value(kind),
       relativePath = Value(relativePath),
       mimeType = Value(mimeType),
       lifecycleState = Value(lifecycleState),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<MediaAsset> custom({
    Expression<String>? id,
    Expression<String>? ownerNoteId,
    Expression<String>? kind,
    Expression<String>? relativePath,
    Expression<String>? mimeType,
    Expression<int>? sizeBytes,
    Expression<String>? sha256,
    Expression<String>? lifecycleState,
    Expression<int>? createdAtUtc,
    Expression<int>? updatedAtUtc,
    Expression<int>? deletedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (ownerNoteId != null) 'owner_note_id': ownerNoteId,
      if (kind != null) 'kind': kind,
      if (relativePath != null) 'relative_path': relativePath,
      if (mimeType != null) 'mime_type': mimeType,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
      if (lifecycleState != null) 'lifecycle_state': lifecycleState,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (deletedAtUtc != null) 'deleted_at_utc': deletedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? ownerNoteId,
    Value<AssetKind>? kind,
    Value<String>? relativePath,
    Value<String>? mimeType,
    Value<int>? sizeBytes,
    Value<String?>? sha256,
    Value<AssetLifecycle>? lifecycleState,
    Value<int>? createdAtUtc,
    Value<int>? updatedAtUtc,
    Value<int?>? deletedAtUtc,
    Value<int>? rowid,
  }) {
    return MediaAssetsCompanion(
      id: id ?? this.id,
      ownerNoteId: ownerNoteId ?? this.ownerNoteId,
      kind: kind ?? this.kind,
      relativePath: relativePath ?? this.relativePath,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      lifecycleState: lifecycleState ?? this.lifecycleState,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ownerNoteId.present) {
      map['owner_note_id'] = Variable<String>(ownerNoteId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(
        $MediaAssetsTable.$converterkind.toSql(kind.value),
      );
    }
    if (relativePath.present) {
      map['relative_path'] = Variable<String>(relativePath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (lifecycleState.present) {
      map['lifecycle_state'] = Variable<String>(
        $MediaAssetsTable.$converterlifecycleState.toSql(lifecycleState.value),
      );
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<int>(updatedAtUtc.value);
    }
    if (deletedAtUtc.present) {
      map['deleted_at_utc'] = Variable<int>(deletedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaAssetsCompanion(')
          ..write('id: $id, ')
          ..write('ownerNoteId: $ownerNoteId, ')
          ..write('kind: $kind, ')
          ..write('relativePath: $relativePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('lifecycleState: $lifecycleState, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('deletedAtUtc: $deletedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AudioRecordingsTable extends AudioRecordings
    with TableInfo<$AudioRecordingsTable, AudioRecording> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AudioRecordingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media_assets (id)',
    ),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codecMeta = const VerificationMeta('codec');
  @override
  late final GeneratedColumn<String> codec = GeneratedColumn<String>(
    'codec',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sampleRateHzMeta = const VerificationMeta(
    'sampleRateHz',
  );
  @override
  late final GeneratedColumn<int> sampleRateHz = GeneratedColumn<int>(
    'sample_rate_hz',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelsMeta = const VerificationMeta(
    'channels',
  );
  @override
  late final GeneratedColumn<int> channels = GeneratedColumn<int>(
    'channels',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtUtcMeta = const VerificationMeta(
    'recordedAtUtc',
  );
  @override
  late final GeneratedColumn<int> recordedAtUtc = GeneratedColumn<int>(
    'recorded_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    assetId,
    durationMs,
    codec,
    sampleRateHz,
    channels,
    recordedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'audio_recordings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AudioRecording> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_assetIdMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('codec')) {
      context.handle(
        _codecMeta,
        codec.isAcceptableOrUnknown(data['codec']!, _codecMeta),
      );
    } else if (isInserting) {
      context.missing(_codecMeta);
    }
    if (data.containsKey('sample_rate_hz')) {
      context.handle(
        _sampleRateHzMeta,
        sampleRateHz.isAcceptableOrUnknown(
          data['sample_rate_hz']!,
          _sampleRateHzMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sampleRateHzMeta);
    }
    if (data.containsKey('channels')) {
      context.handle(
        _channelsMeta,
        channels.isAcceptableOrUnknown(data['channels']!, _channelsMeta),
      );
    } else if (isInserting) {
      context.missing(_channelsMeta);
    }
    if (data.containsKey('recorded_at_utc')) {
      context.handle(
        _recordedAtUtcMeta,
        recordedAtUtc.isAcceptableOrUnknown(
          data['recorded_at_utc']!,
          _recordedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recordedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {assetId};
  @override
  AudioRecording map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AudioRecording(
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      codec: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}codec'],
      )!,
      sampleRateHz: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_rate_hz'],
      )!,
      channels: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}channels'],
      )!,
      recordedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at_utc'],
      )!,
    );
  }

  @override
  $AudioRecordingsTable createAlias(String alias) {
    return $AudioRecordingsTable(attachedDatabase, alias);
  }
}

class AudioRecording extends DataClass implements Insertable<AudioRecording> {
  final String assetId;
  final int durationMs;
  final String codec;
  final int sampleRateHz;
  final int channels;
  final int recordedAtUtc;
  const AudioRecording({
    required this.assetId,
    required this.durationMs,
    required this.codec,
    required this.sampleRateHz,
    required this.channels,
    required this.recordedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['asset_id'] = Variable<String>(assetId);
    map['duration_ms'] = Variable<int>(durationMs);
    map['codec'] = Variable<String>(codec);
    map['sample_rate_hz'] = Variable<int>(sampleRateHz);
    map['channels'] = Variable<int>(channels);
    map['recorded_at_utc'] = Variable<int>(recordedAtUtc);
    return map;
  }

  AudioRecordingsCompanion toCompanion(bool nullToAbsent) {
    return AudioRecordingsCompanion(
      assetId: Value(assetId),
      durationMs: Value(durationMs),
      codec: Value(codec),
      sampleRateHz: Value(sampleRateHz),
      channels: Value(channels),
      recordedAtUtc: Value(recordedAtUtc),
    );
  }

  factory AudioRecording.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AudioRecording(
      assetId: serializer.fromJson<String>(json['assetId']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      codec: serializer.fromJson<String>(json['codec']),
      sampleRateHz: serializer.fromJson<int>(json['sampleRateHz']),
      channels: serializer.fromJson<int>(json['channels']),
      recordedAtUtc: serializer.fromJson<int>(json['recordedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'assetId': serializer.toJson<String>(assetId),
      'durationMs': serializer.toJson<int>(durationMs),
      'codec': serializer.toJson<String>(codec),
      'sampleRateHz': serializer.toJson<int>(sampleRateHz),
      'channels': serializer.toJson<int>(channels),
      'recordedAtUtc': serializer.toJson<int>(recordedAtUtc),
    };
  }

  AudioRecording copyWith({
    String? assetId,
    int? durationMs,
    String? codec,
    int? sampleRateHz,
    int? channels,
    int? recordedAtUtc,
  }) => AudioRecording(
    assetId: assetId ?? this.assetId,
    durationMs: durationMs ?? this.durationMs,
    codec: codec ?? this.codec,
    sampleRateHz: sampleRateHz ?? this.sampleRateHz,
    channels: channels ?? this.channels,
    recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
  );
  AudioRecording copyWithCompanion(AudioRecordingsCompanion data) {
    return AudioRecording(
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      codec: data.codec.present ? data.codec.value : this.codec,
      sampleRateHz: data.sampleRateHz.present
          ? data.sampleRateHz.value
          : this.sampleRateHz,
      channels: data.channels.present ? data.channels.value : this.channels,
      recordedAtUtc: data.recordedAtUtc.present
          ? data.recordedAtUtc.value
          : this.recordedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AudioRecording(')
          ..write('assetId: $assetId, ')
          ..write('durationMs: $durationMs, ')
          ..write('codec: $codec, ')
          ..write('sampleRateHz: $sampleRateHz, ')
          ..write('channels: $channels, ')
          ..write('recordedAtUtc: $recordedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    assetId,
    durationMs,
    codec,
    sampleRateHz,
    channels,
    recordedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AudioRecording &&
          other.assetId == this.assetId &&
          other.durationMs == this.durationMs &&
          other.codec == this.codec &&
          other.sampleRateHz == this.sampleRateHz &&
          other.channels == this.channels &&
          other.recordedAtUtc == this.recordedAtUtc);
}

class AudioRecordingsCompanion extends UpdateCompanion<AudioRecording> {
  final Value<String> assetId;
  final Value<int> durationMs;
  final Value<String> codec;
  final Value<int> sampleRateHz;
  final Value<int> channels;
  final Value<int> recordedAtUtc;
  final Value<int> rowid;
  const AudioRecordingsCompanion({
    this.assetId = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.codec = const Value.absent(),
    this.sampleRateHz = const Value.absent(),
    this.channels = const Value.absent(),
    this.recordedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AudioRecordingsCompanion.insert({
    required String assetId,
    required int durationMs,
    required String codec,
    required int sampleRateHz,
    required int channels,
    required int recordedAtUtc,
    this.rowid = const Value.absent(),
  }) : assetId = Value(assetId),
       durationMs = Value(durationMs),
       codec = Value(codec),
       sampleRateHz = Value(sampleRateHz),
       channels = Value(channels),
       recordedAtUtc = Value(recordedAtUtc);
  static Insertable<AudioRecording> custom({
    Expression<String>? assetId,
    Expression<int>? durationMs,
    Expression<String>? codec,
    Expression<int>? sampleRateHz,
    Expression<int>? channels,
    Expression<int>? recordedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (assetId != null) 'asset_id': assetId,
      if (durationMs != null) 'duration_ms': durationMs,
      if (codec != null) 'codec': codec,
      if (sampleRateHz != null) 'sample_rate_hz': sampleRateHz,
      if (channels != null) 'channels': channels,
      if (recordedAtUtc != null) 'recorded_at_utc': recordedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AudioRecordingsCompanion copyWith({
    Value<String>? assetId,
    Value<int>? durationMs,
    Value<String>? codec,
    Value<int>? sampleRateHz,
    Value<int>? channels,
    Value<int>? recordedAtUtc,
    Value<int>? rowid,
  }) {
    return AudioRecordingsCompanion(
      assetId: assetId ?? this.assetId,
      durationMs: durationMs ?? this.durationMs,
      codec: codec ?? this.codec,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      channels: channels ?? this.channels,
      recordedAtUtc: recordedAtUtc ?? this.recordedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (codec.present) {
      map['codec'] = Variable<String>(codec.value);
    }
    if (sampleRateHz.present) {
      map['sample_rate_hz'] = Variable<int>(sampleRateHz.value);
    }
    if (channels.present) {
      map['channels'] = Variable<int>(channels.value);
    }
    if (recordedAtUtc.present) {
      map['recorded_at_utc'] = Variable<int>(recordedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AudioRecordingsCompanion(')
          ..write('assetId: $assetId, ')
          ..write('durationMs: $durationMs, ')
          ..write('codec: $codec, ')
          ..write('sampleRateHz: $sampleRateHz, ')
          ..write('channels: $channels, ')
          ..write('recordedAtUtc: $recordedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TranscriptRevisionsTable extends TranscriptRevisions
    with TableInfo<$TranscriptRevisionsTable, TranscriptRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TranscriptRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteIdMeta = const VerificationMeta('noteId');
  @override
  late final GeneratedColumn<String> noteId = GeneratedColumn<String>(
    'note_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES notes (id)',
    ),
  );
  static const VerificationMeta _audioAssetIdMeta = const VerificationMeta(
    'audioAssetId',
  );
  @override
  late final GeneratedColumn<String> audioAssetId = GeneratedColumn<String>(
    'audio_asset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES media_assets (id)',
    ),
  );
  static const VerificationMeta _engineIdMeta = const VerificationMeta(
    'engineId',
  );
  @override
  late final GeneratedColumn<String> engineId = GeneratedColumn<String>(
    'engine_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawTextMeta = const VerificationMeta(
    'rawText',
  );
  @override
  late final GeneratedColumn<String> rawText = GeneratedColumn<String>(
    'raw_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _segmentsJsonMeta = const VerificationMeta(
    'segmentsJson',
  );
  @override
  late final GeneratedColumn<String> segmentsJson = GeneratedColumn<String>(
    'segments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TranscriptState, String> state =
      GeneratedColumn<String>(
        'state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<TranscriptState>(
        $TranscriptRevisionsTable.$converterstate,
      );
  static const VerificationMeta _errorMessageMeta = const VerificationMeta(
    'errorMessage',
  );
  @override
  late final GeneratedColumn<String> errorMessage = GeneratedColumn<String>(
    'error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<int> createdAtUtc = GeneratedColumn<int>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acceptedAtUtcMeta = const VerificationMeta(
    'acceptedAtUtc',
  );
  @override
  late final GeneratedColumn<int> acceptedAtUtc = GeneratedColumn<int>(
    'accepted_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    noteId,
    audioAssetId,
    engineId,
    modelId,
    language,
    rawText,
    segmentsJson,
    state,
    errorMessage,
    createdAtUtc,
    acceptedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transcript_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<TranscriptRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('note_id')) {
      context.handle(
        _noteIdMeta,
        noteId.isAcceptableOrUnknown(data['note_id']!, _noteIdMeta),
      );
    } else if (isInserting) {
      context.missing(_noteIdMeta);
    }
    if (data.containsKey('audio_asset_id')) {
      context.handle(
        _audioAssetIdMeta,
        audioAssetId.isAcceptableOrUnknown(
          data['audio_asset_id']!,
          _audioAssetIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_audioAssetIdMeta);
    }
    if (data.containsKey('engine_id')) {
      context.handle(
        _engineIdMeta,
        engineId.isAcceptableOrUnknown(data['engine_id']!, _engineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_engineIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    } else if (isInserting) {
      context.missing(_languageMeta);
    }
    if (data.containsKey('raw_text')) {
      context.handle(
        _rawTextMeta,
        rawText.isAcceptableOrUnknown(data['raw_text']!, _rawTextMeta),
      );
    }
    if (data.containsKey('segments_json')) {
      context.handle(
        _segmentsJsonMeta,
        segmentsJson.isAcceptableOrUnknown(
          data['segments_json']!,
          _segmentsJsonMeta,
        ),
      );
    }
    if (data.containsKey('error_message')) {
      context.handle(
        _errorMessageMeta,
        errorMessage.isAcceptableOrUnknown(
          data['error_message']!,
          _errorMessageMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('accepted_at_utc')) {
      context.handle(
        _acceptedAtUtcMeta,
        acceptedAtUtc.isAcceptableOrUnknown(
          data['accepted_at_utc']!,
          _acceptedAtUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TranscriptRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TranscriptRevision(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      noteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note_id'],
      )!,
      audioAssetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}audio_asset_id'],
      )!,
      engineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      rawText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_text'],
      )!,
      segmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}segments_json'],
      ),
      state: $TranscriptRevisionsTable.$converterstate.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}state'],
        )!,
      ),
      errorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_message'],
      ),
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_utc'],
      )!,
      acceptedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_at_utc'],
      ),
    );
  }

  @override
  $TranscriptRevisionsTable createAlias(String alias) {
    return $TranscriptRevisionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TranscriptState, String, String> $converterstate =
      const EnumNameConverter<TranscriptState>(TranscriptState.values);
}

class TranscriptRevision extends DataClass
    implements Insertable<TranscriptRevision> {
  final String id;
  final String noteId;
  final String audioAssetId;
  final String engineId;
  final String modelId;
  final String language;
  final String rawText;
  final String? segmentsJson;
  final TranscriptState state;
  final String? errorMessage;
  final int createdAtUtc;
  final int? acceptedAtUtc;
  const TranscriptRevision({
    required this.id,
    required this.noteId,
    required this.audioAssetId,
    required this.engineId,
    required this.modelId,
    required this.language,
    required this.rawText,
    this.segmentsJson,
    required this.state,
    this.errorMessage,
    required this.createdAtUtc,
    this.acceptedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['note_id'] = Variable<String>(noteId);
    map['audio_asset_id'] = Variable<String>(audioAssetId);
    map['engine_id'] = Variable<String>(engineId);
    map['model_id'] = Variable<String>(modelId);
    map['language'] = Variable<String>(language);
    map['raw_text'] = Variable<String>(rawText);
    if (!nullToAbsent || segmentsJson != null) {
      map['segments_json'] = Variable<String>(segmentsJson);
    }
    {
      map['state'] = Variable<String>(
        $TranscriptRevisionsTable.$converterstate.toSql(state),
      );
    }
    if (!nullToAbsent || errorMessage != null) {
      map['error_message'] = Variable<String>(errorMessage);
    }
    map['created_at_utc'] = Variable<int>(createdAtUtc);
    if (!nullToAbsent || acceptedAtUtc != null) {
      map['accepted_at_utc'] = Variable<int>(acceptedAtUtc);
    }
    return map;
  }

  TranscriptRevisionsCompanion toCompanion(bool nullToAbsent) {
    return TranscriptRevisionsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      audioAssetId: Value(audioAssetId),
      engineId: Value(engineId),
      modelId: Value(modelId),
      language: Value(language),
      rawText: Value(rawText),
      segmentsJson: segmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(segmentsJson),
      state: Value(state),
      errorMessage: errorMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(errorMessage),
      createdAtUtc: Value(createdAtUtc),
      acceptedAtUtc: acceptedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(acceptedAtUtc),
    );
  }

  factory TranscriptRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TranscriptRevision(
      id: serializer.fromJson<String>(json['id']),
      noteId: serializer.fromJson<String>(json['noteId']),
      audioAssetId: serializer.fromJson<String>(json['audioAssetId']),
      engineId: serializer.fromJson<String>(json['engineId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      language: serializer.fromJson<String>(json['language']),
      rawText: serializer.fromJson<String>(json['rawText']),
      segmentsJson: serializer.fromJson<String?>(json['segmentsJson']),
      state: $TranscriptRevisionsTable.$converterstate.fromJson(
        serializer.fromJson<String>(json['state']),
      ),
      errorMessage: serializer.fromJson<String?>(json['errorMessage']),
      createdAtUtc: serializer.fromJson<int>(json['createdAtUtc']),
      acceptedAtUtc: serializer.fromJson<int?>(json['acceptedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'noteId': serializer.toJson<String>(noteId),
      'audioAssetId': serializer.toJson<String>(audioAssetId),
      'engineId': serializer.toJson<String>(engineId),
      'modelId': serializer.toJson<String>(modelId),
      'language': serializer.toJson<String>(language),
      'rawText': serializer.toJson<String>(rawText),
      'segmentsJson': serializer.toJson<String?>(segmentsJson),
      'state': serializer.toJson<String>(
        $TranscriptRevisionsTable.$converterstate.toJson(state),
      ),
      'errorMessage': serializer.toJson<String?>(errorMessage),
      'createdAtUtc': serializer.toJson<int>(createdAtUtc),
      'acceptedAtUtc': serializer.toJson<int?>(acceptedAtUtc),
    };
  }

  TranscriptRevision copyWith({
    String? id,
    String? noteId,
    String? audioAssetId,
    String? engineId,
    String? modelId,
    String? language,
    String? rawText,
    Value<String?> segmentsJson = const Value.absent(),
    TranscriptState? state,
    Value<String?> errorMessage = const Value.absent(),
    int? createdAtUtc,
    Value<int?> acceptedAtUtc = const Value.absent(),
  }) => TranscriptRevision(
    id: id ?? this.id,
    noteId: noteId ?? this.noteId,
    audioAssetId: audioAssetId ?? this.audioAssetId,
    engineId: engineId ?? this.engineId,
    modelId: modelId ?? this.modelId,
    language: language ?? this.language,
    rawText: rawText ?? this.rawText,
    segmentsJson: segmentsJson.present ? segmentsJson.value : this.segmentsJson,
    state: state ?? this.state,
    errorMessage: errorMessage.present ? errorMessage.value : this.errorMessage,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    acceptedAtUtc: acceptedAtUtc.present
        ? acceptedAtUtc.value
        : this.acceptedAtUtc,
  );
  TranscriptRevision copyWithCompanion(TranscriptRevisionsCompanion data) {
    return TranscriptRevision(
      id: data.id.present ? data.id.value : this.id,
      noteId: data.noteId.present ? data.noteId.value : this.noteId,
      audioAssetId: data.audioAssetId.present
          ? data.audioAssetId.value
          : this.audioAssetId,
      engineId: data.engineId.present ? data.engineId.value : this.engineId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      language: data.language.present ? data.language.value : this.language,
      rawText: data.rawText.present ? data.rawText.value : this.rawText,
      segmentsJson: data.segmentsJson.present
          ? data.segmentsJson.value
          : this.segmentsJson,
      state: data.state.present ? data.state.value : this.state,
      errorMessage: data.errorMessage.present
          ? data.errorMessage.value
          : this.errorMessage,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      acceptedAtUtc: data.acceptedAtUtc.present
          ? data.acceptedAtUtc.value
          : this.acceptedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptRevision(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('audioAssetId: $audioAssetId, ')
          ..write('engineId: $engineId, ')
          ..write('modelId: $modelId, ')
          ..write('language: $language, ')
          ..write('rawText: $rawText, ')
          ..write('segmentsJson: $segmentsJson, ')
          ..write('state: $state, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('acceptedAtUtc: $acceptedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    audioAssetId,
    engineId,
    modelId,
    language,
    rawText,
    segmentsJson,
    state,
    errorMessage,
    createdAtUtc,
    acceptedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptRevision &&
          other.id == this.id &&
          other.noteId == this.noteId &&
          other.audioAssetId == this.audioAssetId &&
          other.engineId == this.engineId &&
          other.modelId == this.modelId &&
          other.language == this.language &&
          other.rawText == this.rawText &&
          other.segmentsJson == this.segmentsJson &&
          other.state == this.state &&
          other.errorMessage == this.errorMessage &&
          other.createdAtUtc == this.createdAtUtc &&
          other.acceptedAtUtc == this.acceptedAtUtc);
}

class TranscriptRevisionsCompanion extends UpdateCompanion<TranscriptRevision> {
  final Value<String> id;
  final Value<String> noteId;
  final Value<String> audioAssetId;
  final Value<String> engineId;
  final Value<String> modelId;
  final Value<String> language;
  final Value<String> rawText;
  final Value<String?> segmentsJson;
  final Value<TranscriptState> state;
  final Value<String?> errorMessage;
  final Value<int> createdAtUtc;
  final Value<int?> acceptedAtUtc;
  final Value<int> rowid;
  const TranscriptRevisionsCompanion({
    this.id = const Value.absent(),
    this.noteId = const Value.absent(),
    this.audioAssetId = const Value.absent(),
    this.engineId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.language = const Value.absent(),
    this.rawText = const Value.absent(),
    this.segmentsJson = const Value.absent(),
    this.state = const Value.absent(),
    this.errorMessage = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.acceptedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TranscriptRevisionsCompanion.insert({
    required String id,
    required String noteId,
    required String audioAssetId,
    required String engineId,
    required String modelId,
    required String language,
    this.rawText = const Value.absent(),
    this.segmentsJson = const Value.absent(),
    required TranscriptState state,
    this.errorMessage = const Value.absent(),
    required int createdAtUtc,
    this.acceptedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       noteId = Value(noteId),
       audioAssetId = Value(audioAssetId),
       engineId = Value(engineId),
       modelId = Value(modelId),
       language = Value(language),
       state = Value(state),
       createdAtUtc = Value(createdAtUtc);
  static Insertable<TranscriptRevision> custom({
    Expression<String>? id,
    Expression<String>? noteId,
    Expression<String>? audioAssetId,
    Expression<String>? engineId,
    Expression<String>? modelId,
    Expression<String>? language,
    Expression<String>? rawText,
    Expression<String>? segmentsJson,
    Expression<String>? state,
    Expression<String>? errorMessage,
    Expression<int>? createdAtUtc,
    Expression<int>? acceptedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (noteId != null) 'note_id': noteId,
      if (audioAssetId != null) 'audio_asset_id': audioAssetId,
      if (engineId != null) 'engine_id': engineId,
      if (modelId != null) 'model_id': modelId,
      if (language != null) 'language': language,
      if (rawText != null) 'raw_text': rawText,
      if (segmentsJson != null) 'segments_json': segmentsJson,
      if (state != null) 'state': state,
      if (errorMessage != null) 'error_message': errorMessage,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (acceptedAtUtc != null) 'accepted_at_utc': acceptedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TranscriptRevisionsCompanion copyWith({
    Value<String>? id,
    Value<String>? noteId,
    Value<String>? audioAssetId,
    Value<String>? engineId,
    Value<String>? modelId,
    Value<String>? language,
    Value<String>? rawText,
    Value<String?>? segmentsJson,
    Value<TranscriptState>? state,
    Value<String?>? errorMessage,
    Value<int>? createdAtUtc,
    Value<int?>? acceptedAtUtc,
    Value<int>? rowid,
  }) {
    return TranscriptRevisionsCompanion(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      audioAssetId: audioAssetId ?? this.audioAssetId,
      engineId: engineId ?? this.engineId,
      modelId: modelId ?? this.modelId,
      language: language ?? this.language,
      rawText: rawText ?? this.rawText,
      segmentsJson: segmentsJson ?? this.segmentsJson,
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      acceptedAtUtc: acceptedAtUtc ?? this.acceptedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (noteId.present) {
      map['note_id'] = Variable<String>(noteId.value);
    }
    if (audioAssetId.present) {
      map['audio_asset_id'] = Variable<String>(audioAssetId.value);
    }
    if (engineId.present) {
      map['engine_id'] = Variable<String>(engineId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (rawText.present) {
      map['raw_text'] = Variable<String>(rawText.value);
    }
    if (segmentsJson.present) {
      map['segments_json'] = Variable<String>(segmentsJson.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(
        $TranscriptRevisionsTable.$converterstate.toSql(state.value),
      );
    }
    if (errorMessage.present) {
      map['error_message'] = Variable<String>(errorMessage.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<int>(createdAtUtc.value);
    }
    if (acceptedAtUtc.present) {
      map['accepted_at_utc'] = Variable<int>(acceptedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptRevisionsCompanion(')
          ..write('id: $id, ')
          ..write('noteId: $noteId, ')
          ..write('audioAssetId: $audioAssetId, ')
          ..write('engineId: $engineId, ')
          ..write('modelId: $modelId, ')
          ..write('language: $language, ')
          ..write('rawText: $rawText, ')
          ..write('segmentsJson: $segmentsJson, ')
          ..write('state: $state, ')
          ..write('errorMessage: $errorMessage, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('acceptedAtUtc: $acceptedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NotesTable notes = $NotesTable(this);
  late final $MediaAssetsTable mediaAssets = $MediaAssetsTable(this);
  late final $AudioRecordingsTable audioRecordings = $AudioRecordingsTable(
    this,
  );
  late final $TranscriptRevisionsTable transcriptRevisions =
      $TranscriptRevisionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    notes,
    mediaAssets,
    audioRecordings,
    transcriptRevisions,
  ];
}

typedef $$NotesTableCreateCompanionBuilder =
    NotesCompanion Function({
      required String id,
      Value<String?> projectId,
      Value<String?> title,
      Value<NoteStatus> status,
      required String documentJson,
      required String documentPlainText,
      required SourceKind sourceKind,
      Value<bool> isPinned,
      Value<bool> isFavorite,
      Value<int?> favoritedAtUtc,
      Value<int?> completedAtUtc,
      Value<int?> eventAtUtc,
      required int createdAtUtc,
      required int updatedAtUtc,
      Value<int?> deletedAtUtc,
      Value<int> revision,
      Value<int> rowid,
    });
typedef $$NotesTableUpdateCompanionBuilder =
    NotesCompanion Function({
      Value<String> id,
      Value<String?> projectId,
      Value<String?> title,
      Value<NoteStatus> status,
      Value<String> documentJson,
      Value<String> documentPlainText,
      Value<SourceKind> sourceKind,
      Value<bool> isPinned,
      Value<bool> isFavorite,
      Value<int?> favoritedAtUtc,
      Value<int?> completedAtUtc,
      Value<int?> eventAtUtc,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<int?> deletedAtUtc,
      Value<int> revision,
      Value<int> rowid,
    });

final class $$NotesTableReferences
    extends BaseReferences<_$AppDatabase, $NotesTable, Note> {
  $$NotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MediaAssetsTable, List<MediaAsset>>
  _mediaAssetsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.mediaAssets,
    aliasName: 'notes__id__media_assets__owner_note_id',
  );

  $$MediaAssetsTableProcessedTableManager get mediaAssetsRefs {
    final manager = $$MediaAssetsTableTableManager(
      $_db,
      $_db.mediaAssets,
    ).filter((f) => f.ownerNoteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_mediaAssetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TranscriptRevisionsTable,
    List<TranscriptRevision>
  >
  _transcriptRevisionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.transcriptRevisions,
        aliasName: 'notes__id__transcript_revisions__note_id',
      );

  $$TranscriptRevisionsTableProcessedTableManager get transcriptRevisionsRefs {
    final manager = $$TranscriptRevisionsTableTableManager(
      $_db,
      $_db.transcriptRevisions,
    ).filter((f) => f.noteId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _transcriptRevisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NotesTableFilterComposer extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<NoteStatus, NoteStatus, String> get status =>
      $composableBuilder(
        column: $table.status,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get documentPlainText => $composableBuilder(
    column: $table.documentPlainText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<SourceKind, SourceKind, String>
  get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get favoritedAtUtc => $composableBuilder(
    column: $table.favoritedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get eventAtUtc => $composableBuilder(
    column: $table.eventAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> mediaAssetsRefs(
    Expression<bool> Function($$MediaAssetsTableFilterComposer f) f,
  ) {
    final $$MediaAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.ownerNoteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> transcriptRevisionsRefs(
    Expression<bool> Function($$TranscriptRevisionsTableFilterComposer f) f,
  ) {
    final $$TranscriptRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transcriptRevisions,
      getReferencedColumn: (t) => t.noteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TranscriptRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.transcriptRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NotesTableOrderingComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get documentPlainText => $composableBuilder(
    column: $table.documentPlainText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get favoritedAtUtc => $composableBuilder(
    column: $table.favoritedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get eventAtUtc => $composableBuilder(
    column: $table.eventAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NotesTable> {
  $$NotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumnWithTypeConverter<NoteStatus, String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get documentJson => $composableBuilder(
    column: $table.documentJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get documentPlainText => $composableBuilder(
    column: $table.documentPlainText,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<SourceKind, String> get sourceKind =>
      $composableBuilder(
        column: $table.sourceKind,
        builder: (column) => column,
      );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<int> get favoritedAtUtc => $composableBuilder(
    column: $table.favoritedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get eventAtUtc => $composableBuilder(
    column: $table.eventAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  Expression<T> mediaAssetsRefs<T extends Object>(
    Expression<T> Function($$MediaAssetsTableAnnotationComposer a) f,
  ) {
    final $$MediaAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.ownerNoteId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> transcriptRevisionsRefs<T extends Object>(
    Expression<T> Function($$TranscriptRevisionsTableAnnotationComposer a) f,
  ) {
    final $$TranscriptRevisionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.transcriptRevisions,
          getReferencedColumn: (t) => t.noteId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TranscriptRevisionsTableAnnotationComposer(
                $db: $db,
                $table: $db.transcriptRevisions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$NotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NotesTable,
          Note,
          $$NotesTableFilterComposer,
          $$NotesTableOrderingComposer,
          $$NotesTableAnnotationComposer,
          $$NotesTableCreateCompanionBuilder,
          $$NotesTableUpdateCompanionBuilder,
          (Note, $$NotesTableReferences),
          Note,
          PrefetchHooks Function({
            bool mediaAssetsRefs,
            bool transcriptRevisionsRefs,
          })
        > {
  $$NotesTableTableManager(_$AppDatabase db, $NotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<NoteStatus> status = const Value.absent(),
                Value<String> documentJson = const Value.absent(),
                Value<String> documentPlainText = const Value.absent(),
                Value<SourceKind> sourceKind = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int?> favoritedAtUtc = const Value.absent(),
                Value<int?> completedAtUtc = const Value.absent(),
                Value<int?> eventAtUtc = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<int?> deletedAtUtc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion(
                id: id,
                projectId: projectId,
                title: title,
                status: status,
                documentJson: documentJson,
                documentPlainText: documentPlainText,
                sourceKind: sourceKind,
                isPinned: isPinned,
                isFavorite: isFavorite,
                favoritedAtUtc: favoritedAtUtc,
                completedAtUtc: completedAtUtc,
                eventAtUtc: eventAtUtc,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                deletedAtUtc: deletedAtUtc,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> projectId = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<NoteStatus> status = const Value.absent(),
                required String documentJson,
                required String documentPlainText,
                required SourceKind sourceKind,
                Value<bool> isPinned = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<int?> favoritedAtUtc = const Value.absent(),
                Value<int?> completedAtUtc = const Value.absent(),
                Value<int?> eventAtUtc = const Value.absent(),
                required int createdAtUtc,
                required int updatedAtUtc,
                Value<int?> deletedAtUtc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NotesCompanion.insert(
                id: id,
                projectId: projectId,
                title: title,
                status: status,
                documentJson: documentJson,
                documentPlainText: documentPlainText,
                sourceKind: sourceKind,
                isPinned: isPinned,
                isFavorite: isFavorite,
                favoritedAtUtc: favoritedAtUtc,
                completedAtUtc: completedAtUtc,
                eventAtUtc: eventAtUtc,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                deletedAtUtc: deletedAtUtc,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$NotesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({mediaAssetsRefs = false, transcriptRevisionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (mediaAssetsRefs) db.mediaAssets,
                    if (transcriptRevisionsRefs) db.transcriptRevisions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (mediaAssetsRefs)
                        await $_getPrefetchedData<
                          Note,
                          $NotesTable,
                          MediaAsset
                        >(
                          currentTable: table,
                          referencedTable: $$NotesTableReferences
                              ._mediaAssetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).mediaAssetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.ownerNoteId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (transcriptRevisionsRefs)
                        await $_getPrefetchedData<
                          Note,
                          $NotesTable,
                          TranscriptRevision
                        >(
                          currentTable: table,
                          referencedTable: $$NotesTableReferences
                              ._transcriptRevisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$NotesTableReferences(
                                db,
                                table,
                                p0,
                              ).transcriptRevisionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.noteId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$NotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NotesTable,
      Note,
      $$NotesTableFilterComposer,
      $$NotesTableOrderingComposer,
      $$NotesTableAnnotationComposer,
      $$NotesTableCreateCompanionBuilder,
      $$NotesTableUpdateCompanionBuilder,
      (Note, $$NotesTableReferences),
      Note,
      PrefetchHooks Function({
        bool mediaAssetsRefs,
        bool transcriptRevisionsRefs,
      })
    >;
typedef $$MediaAssetsTableCreateCompanionBuilder =
    MediaAssetsCompanion Function({
      required String id,
      required String ownerNoteId,
      required AssetKind kind,
      required String relativePath,
      required String mimeType,
      Value<int> sizeBytes,
      Value<String?> sha256,
      required AssetLifecycle lifecycleState,
      required int createdAtUtc,
      required int updatedAtUtc,
      Value<int?> deletedAtUtc,
      Value<int> rowid,
    });
typedef $$MediaAssetsTableUpdateCompanionBuilder =
    MediaAssetsCompanion Function({
      Value<String> id,
      Value<String> ownerNoteId,
      Value<AssetKind> kind,
      Value<String> relativePath,
      Value<String> mimeType,
      Value<int> sizeBytes,
      Value<String?> sha256,
      Value<AssetLifecycle> lifecycleState,
      Value<int> createdAtUtc,
      Value<int> updatedAtUtc,
      Value<int?> deletedAtUtc,
      Value<int> rowid,
    });

final class $$MediaAssetsTableReferences
    extends BaseReferences<_$AppDatabase, $MediaAssetsTable, MediaAsset> {
  $$MediaAssetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NotesTable _ownerNoteIdTable(_$AppDatabase db) =>
      db.notes.createAlias('media_assets__owner_note_id__notes__id');

  $$NotesTableProcessedTableManager get ownerNoteId {
    final $_column = $_itemColumn<String>('owner_note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_ownerNoteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AudioRecordingsTable, List<AudioRecording>>
  _audioRecordingsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.audioRecordings,
    aliasName: 'media_assets__id__audio_recordings__asset_id',
  );

  $$AudioRecordingsTableProcessedTableManager get audioRecordingsRefs {
    final manager = $$AudioRecordingsTableTableManager(
      $_db,
      $_db.audioRecordings,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _audioRecordingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $TranscriptRevisionsTable,
    List<TranscriptRevision>
  >
  _transcriptRevisionsRefsTable(_$AppDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.transcriptRevisions,
        aliasName: 'media_assets__id__transcript_revisions__audio_asset_id',
      );

  $$TranscriptRevisionsTableProcessedTableManager get transcriptRevisionsRefs {
    final manager = $$TranscriptRevisionsTableTableManager(
      $_db,
      $_db.transcriptRevisions,
    ).filter((f) => f.audioAssetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _transcriptRevisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MediaAssetsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AssetKind, AssetKind, String> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<AssetLifecycle, AssetLifecycle, String>
  get lifecycleState => $composableBuilder(
    column: $table.lifecycleState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$NotesTableFilterComposer get ownerNoteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerNoteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> audioRecordingsRefs(
    Expression<bool> Function($$AudioRecordingsTableFilterComposer f) f,
  ) {
    final $$AudioRecordingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.audioRecordings,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AudioRecordingsTableFilterComposer(
            $db: $db,
            $table: $db.audioRecordings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> transcriptRevisionsRefs(
    Expression<bool> Function($$TranscriptRevisionsTableFilterComposer f) f,
  ) {
    final $$TranscriptRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transcriptRevisions,
      getReferencedColumn: (t) => t.audioAssetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TranscriptRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.transcriptRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MediaAssetsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycleState => $composableBuilder(
    column: $table.lifecycleState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotesTableOrderingComposer get ownerNoteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerNoteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$MediaAssetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaAssetsTable> {
  $$MediaAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AssetKind, String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get relativePath => $composableBuilder(
    column: $table.relativePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumnWithTypeConverter<AssetLifecycle, String> get lifecycleState =>
      $composableBuilder(
        column: $table.lifecycleState,
        builder: (column) => column,
      );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => column,
  );

  $$NotesTableAnnotationComposer get ownerNoteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.ownerNoteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> audioRecordingsRefs<T extends Object>(
    Expression<T> Function($$AudioRecordingsTableAnnotationComposer a) f,
  ) {
    final $$AudioRecordingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.audioRecordings,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AudioRecordingsTableAnnotationComposer(
            $db: $db,
            $table: $db.audioRecordings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> transcriptRevisionsRefs<T extends Object>(
    Expression<T> Function($$TranscriptRevisionsTableAnnotationComposer a) f,
  ) {
    final $$TranscriptRevisionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.transcriptRevisions,
          getReferencedColumn: (t) => t.audioAssetId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$TranscriptRevisionsTableAnnotationComposer(
                $db: $db,
                $table: $db.transcriptRevisions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$MediaAssetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaAssetsTable,
          MediaAsset,
          $$MediaAssetsTableFilterComposer,
          $$MediaAssetsTableOrderingComposer,
          $$MediaAssetsTableAnnotationComposer,
          $$MediaAssetsTableCreateCompanionBuilder,
          $$MediaAssetsTableUpdateCompanionBuilder,
          (MediaAsset, $$MediaAssetsTableReferences),
          MediaAsset,
          PrefetchHooks Function({
            bool ownerNoteId,
            bool audioRecordingsRefs,
            bool transcriptRevisionsRefs,
          })
        > {
  $$MediaAssetsTableTableManager(_$AppDatabase db, $MediaAssetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> ownerNoteId = const Value.absent(),
                Value<AssetKind> kind = const Value.absent(),
                Value<String> relativePath = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                Value<AssetLifecycle> lifecycleState = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int> updatedAtUtc = const Value.absent(),
                Value<int?> deletedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaAssetsCompanion(
                id: id,
                ownerNoteId: ownerNoteId,
                kind: kind,
                relativePath: relativePath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                sha256: sha256,
                lifecycleState: lifecycleState,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                deletedAtUtc: deletedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String ownerNoteId,
                required AssetKind kind,
                required String relativePath,
                required String mimeType,
                Value<int> sizeBytes = const Value.absent(),
                Value<String?> sha256 = const Value.absent(),
                required AssetLifecycle lifecycleState,
                required int createdAtUtc,
                required int updatedAtUtc,
                Value<int?> deletedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaAssetsCompanion.insert(
                id: id,
                ownerNoteId: ownerNoteId,
                kind: kind,
                relativePath: relativePath,
                mimeType: mimeType,
                sizeBytes: sizeBytes,
                sha256: sha256,
                lifecycleState: lifecycleState,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                deletedAtUtc: deletedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MediaAssetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                ownerNoteId = false,
                audioRecordingsRefs = false,
                transcriptRevisionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (audioRecordingsRefs) db.audioRecordings,
                    if (transcriptRevisionsRefs) db.transcriptRevisions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (ownerNoteId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.ownerNoteId,
                                    referencedTable:
                                        $$MediaAssetsTableReferences
                                            ._ownerNoteIdTable(db),
                                    referencedColumn:
                                        $$MediaAssetsTableReferences
                                            ._ownerNoteIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (audioRecordingsRefs)
                        await $_getPrefetchedData<
                          MediaAsset,
                          $MediaAssetsTable,
                          AudioRecording
                        >(
                          currentTable: table,
                          referencedTable: $$MediaAssetsTableReferences
                              ._audioRecordingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaAssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).audioRecordingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (transcriptRevisionsRefs)
                        await $_getPrefetchedData<
                          MediaAsset,
                          $MediaAssetsTable,
                          TranscriptRevision
                        >(
                          currentTable: table,
                          referencedTable: $$MediaAssetsTableReferences
                              ._transcriptRevisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$MediaAssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).transcriptRevisionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.audioAssetId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$MediaAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaAssetsTable,
      MediaAsset,
      $$MediaAssetsTableFilterComposer,
      $$MediaAssetsTableOrderingComposer,
      $$MediaAssetsTableAnnotationComposer,
      $$MediaAssetsTableCreateCompanionBuilder,
      $$MediaAssetsTableUpdateCompanionBuilder,
      (MediaAsset, $$MediaAssetsTableReferences),
      MediaAsset,
      PrefetchHooks Function({
        bool ownerNoteId,
        bool audioRecordingsRefs,
        bool transcriptRevisionsRefs,
      })
    >;
typedef $$AudioRecordingsTableCreateCompanionBuilder =
    AudioRecordingsCompanion Function({
      required String assetId,
      required int durationMs,
      required String codec,
      required int sampleRateHz,
      required int channels,
      required int recordedAtUtc,
      Value<int> rowid,
    });
typedef $$AudioRecordingsTableUpdateCompanionBuilder =
    AudioRecordingsCompanion Function({
      Value<String> assetId,
      Value<int> durationMs,
      Value<String> codec,
      Value<int> sampleRateHz,
      Value<int> channels,
      Value<int> recordedAtUtc,
      Value<int> rowid,
    });

final class $$AudioRecordingsTableReferences
    extends
        BaseReferences<_$AppDatabase, $AudioRecordingsTable, AudioRecording> {
  $$AudioRecordingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $MediaAssetsTable _assetIdTable(_$AppDatabase db) => db.mediaAssets
      .createAlias('audio_recordings__asset_id__media_assets__id');

  $$MediaAssetsTableProcessedTableManager get assetId {
    final $_column = $_itemColumn<String>('asset_id')!;

    final manager = $$MediaAssetsTableTableManager(
      $_db,
      $_db.mediaAssets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AudioRecordingsTableFilterComposer
    extends Composer<_$AppDatabase, $AudioRecordingsTable> {
  $$AudioRecordingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codec => $composableBuilder(
    column: $table.codec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get channels => $composableBuilder(
    column: $table.channels,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$MediaAssetsTableFilterComposer get assetId {
    final $$MediaAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AudioRecordingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AudioRecordingsTable> {
  $$AudioRecordingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codec => $composableBuilder(
    column: $table.codec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get channels => $composableBuilder(
    column: $table.channels,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$MediaAssetsTableOrderingComposer get assetId {
    final $$MediaAssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableOrderingComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AudioRecordingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AudioRecordingsTable> {
  $$AudioRecordingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get codec =>
      $composableBuilder(column: $table.codec, builder: (column) => column);

  GeneratedColumn<int> get sampleRateHz => $composableBuilder(
    column: $table.sampleRateHz,
    builder: (column) => column,
  );

  GeneratedColumn<int> get channels =>
      $composableBuilder(column: $table.channels, builder: (column) => column);

  GeneratedColumn<int> get recordedAtUtc => $composableBuilder(
    column: $table.recordedAtUtc,
    builder: (column) => column,
  );

  $$MediaAssetsTableAnnotationComposer get assetId {
    final $$MediaAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AudioRecordingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AudioRecordingsTable,
          AudioRecording,
          $$AudioRecordingsTableFilterComposer,
          $$AudioRecordingsTableOrderingComposer,
          $$AudioRecordingsTableAnnotationComposer,
          $$AudioRecordingsTableCreateCompanionBuilder,
          $$AudioRecordingsTableUpdateCompanionBuilder,
          (AudioRecording, $$AudioRecordingsTableReferences),
          AudioRecording,
          PrefetchHooks Function({bool assetId})
        > {
  $$AudioRecordingsTableTableManager(
    _$AppDatabase db,
    $AudioRecordingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AudioRecordingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AudioRecordingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AudioRecordingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> assetId = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<String> codec = const Value.absent(),
                Value<int> sampleRateHz = const Value.absent(),
                Value<int> channels = const Value.absent(),
                Value<int> recordedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AudioRecordingsCompanion(
                assetId: assetId,
                durationMs: durationMs,
                codec: codec,
                sampleRateHz: sampleRateHz,
                channels: channels,
                recordedAtUtc: recordedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String assetId,
                required int durationMs,
                required String codec,
                required int sampleRateHz,
                required int channels,
                required int recordedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => AudioRecordingsCompanion.insert(
                assetId: assetId,
                durationMs: durationMs,
                codec: codec,
                sampleRateHz: sampleRateHz,
                channels: channels,
                recordedAtUtc: recordedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AudioRecordingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({assetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (assetId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assetId,
                                referencedTable:
                                    $$AudioRecordingsTableReferences
                                        ._assetIdTable(db),
                                referencedColumn:
                                    $$AudioRecordingsTableReferences
                                        ._assetIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AudioRecordingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AudioRecordingsTable,
      AudioRecording,
      $$AudioRecordingsTableFilterComposer,
      $$AudioRecordingsTableOrderingComposer,
      $$AudioRecordingsTableAnnotationComposer,
      $$AudioRecordingsTableCreateCompanionBuilder,
      $$AudioRecordingsTableUpdateCompanionBuilder,
      (AudioRecording, $$AudioRecordingsTableReferences),
      AudioRecording,
      PrefetchHooks Function({bool assetId})
    >;
typedef $$TranscriptRevisionsTableCreateCompanionBuilder =
    TranscriptRevisionsCompanion Function({
      required String id,
      required String noteId,
      required String audioAssetId,
      required String engineId,
      required String modelId,
      required String language,
      Value<String> rawText,
      Value<String?> segmentsJson,
      required TranscriptState state,
      Value<String?> errorMessage,
      required int createdAtUtc,
      Value<int?> acceptedAtUtc,
      Value<int> rowid,
    });
typedef $$TranscriptRevisionsTableUpdateCompanionBuilder =
    TranscriptRevisionsCompanion Function({
      Value<String> id,
      Value<String> noteId,
      Value<String> audioAssetId,
      Value<String> engineId,
      Value<String> modelId,
      Value<String> language,
      Value<String> rawText,
      Value<String?> segmentsJson,
      Value<TranscriptState> state,
      Value<String?> errorMessage,
      Value<int> createdAtUtc,
      Value<int?> acceptedAtUtc,
      Value<int> rowid,
    });

final class $$TranscriptRevisionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $TranscriptRevisionsTable,
          TranscriptRevision
        > {
  $$TranscriptRevisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NotesTable _noteIdTable(_$AppDatabase db) =>
      db.notes.createAlias('transcript_revisions__note_id__notes__id');

  $$NotesTableProcessedTableManager get noteId {
    final $_column = $_itemColumn<String>('note_id')!;

    final manager = $$NotesTableTableManager(
      $_db,
      $_db.notes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_noteIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $MediaAssetsTable _audioAssetIdTable(_$AppDatabase db) => db
      .mediaAssets
      .createAlias('transcript_revisions__audio_asset_id__media_assets__id');

  $$MediaAssetsTableProcessedTableManager get audioAssetId {
    final $_column = $_itemColumn<String>('audio_asset_id')!;

    final manager = $$MediaAssetsTableTableManager(
      $_db,
      $_db.mediaAssets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_audioAssetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TranscriptRevisionsTableFilterComposer
    extends Composer<_$AppDatabase, $TranscriptRevisionsTable> {
  $$TranscriptRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engineId => $composableBuilder(
    column: $table.engineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get segmentsJson => $composableBuilder(
    column: $table.segmentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TranscriptState, TranscriptState, String>
  get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptedAtUtc => $composableBuilder(
    column: $table.acceptedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  $$NotesTableFilterComposer get noteId {
    final $$NotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableFilterComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaAssetsTableFilterComposer get audioAssetId {
    final $$MediaAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.audioAssetId,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableFilterComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptRevisionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TranscriptRevisionsTable> {
  $$TranscriptRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engineId => $composableBuilder(
    column: $table.engineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawText => $composableBuilder(
    column: $table.rawText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get segmentsJson => $composableBuilder(
    column: $table.segmentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedAtUtc => $composableBuilder(
    column: $table.acceptedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  $$NotesTableOrderingComposer get noteId {
    final $$NotesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableOrderingComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaAssetsTableOrderingComposer get audioAssetId {
    final $$MediaAssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.audioAssetId,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableOrderingComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptRevisionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TranscriptRevisionsTable> {
  $$TranscriptRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get engineId =>
      $composableBuilder(column: $table.engineId, builder: (column) => column);

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get rawText =>
      $composableBuilder(column: $table.rawText, builder: (column) => column);

  GeneratedColumn<String> get segmentsJson => $composableBuilder(
    column: $table.segmentsJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<TranscriptState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get errorMessage => $composableBuilder(
    column: $table.errorMessage,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acceptedAtUtc => $composableBuilder(
    column: $table.acceptedAtUtc,
    builder: (column) => column,
  );

  $$NotesTableAnnotationComposer get noteId {
    final $$NotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.noteId,
      referencedTable: $db.notes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NotesTableAnnotationComposer(
            $db: $db,
            $table: $db.notes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$MediaAssetsTableAnnotationComposer get audioAssetId {
    final $$MediaAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.audioAssetId,
      referencedTable: $db.mediaAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MediaAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.mediaAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TranscriptRevisionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TranscriptRevisionsTable,
          TranscriptRevision,
          $$TranscriptRevisionsTableFilterComposer,
          $$TranscriptRevisionsTableOrderingComposer,
          $$TranscriptRevisionsTableAnnotationComposer,
          $$TranscriptRevisionsTableCreateCompanionBuilder,
          $$TranscriptRevisionsTableUpdateCompanionBuilder,
          (TranscriptRevision, $$TranscriptRevisionsTableReferences),
          TranscriptRevision,
          PrefetchHooks Function({bool noteId, bool audioAssetId})
        > {
  $$TranscriptRevisionsTableTableManager(
    _$AppDatabase db,
    $TranscriptRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TranscriptRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TranscriptRevisionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TranscriptRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> noteId = const Value.absent(),
                Value<String> audioAssetId = const Value.absent(),
                Value<String> engineId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String> rawText = const Value.absent(),
                Value<String?> segmentsJson = const Value.absent(),
                Value<TranscriptState> state = const Value.absent(),
                Value<String?> errorMessage = const Value.absent(),
                Value<int> createdAtUtc = const Value.absent(),
                Value<int?> acceptedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TranscriptRevisionsCompanion(
                id: id,
                noteId: noteId,
                audioAssetId: audioAssetId,
                engineId: engineId,
                modelId: modelId,
                language: language,
                rawText: rawText,
                segmentsJson: segmentsJson,
                state: state,
                errorMessage: errorMessage,
                createdAtUtc: createdAtUtc,
                acceptedAtUtc: acceptedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String noteId,
                required String audioAssetId,
                required String engineId,
                required String modelId,
                required String language,
                Value<String> rawText = const Value.absent(),
                Value<String?> segmentsJson = const Value.absent(),
                required TranscriptState state,
                Value<String?> errorMessage = const Value.absent(),
                required int createdAtUtc,
                Value<int?> acceptedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TranscriptRevisionsCompanion.insert(
                id: id,
                noteId: noteId,
                audioAssetId: audioAssetId,
                engineId: engineId,
                modelId: modelId,
                language: language,
                rawText: rawText,
                segmentsJson: segmentsJson,
                state: state,
                errorMessage: errorMessage,
                createdAtUtc: createdAtUtc,
                acceptedAtUtc: acceptedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$TranscriptRevisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({noteId = false, audioAssetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (noteId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.noteId,
                                referencedTable:
                                    $$TranscriptRevisionsTableReferences
                                        ._noteIdTable(db),
                                referencedColumn:
                                    $$TranscriptRevisionsTableReferences
                                        ._noteIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (audioAssetId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.audioAssetId,
                                referencedTable:
                                    $$TranscriptRevisionsTableReferences
                                        ._audioAssetIdTable(db),
                                referencedColumn:
                                    $$TranscriptRevisionsTableReferences
                                        ._audioAssetIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TranscriptRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TranscriptRevisionsTable,
      TranscriptRevision,
      $$TranscriptRevisionsTableFilterComposer,
      $$TranscriptRevisionsTableOrderingComposer,
      $$TranscriptRevisionsTableAnnotationComposer,
      $$TranscriptRevisionsTableCreateCompanionBuilder,
      $$TranscriptRevisionsTableUpdateCompanionBuilder,
      (TranscriptRevision, $$TranscriptRevisionsTableReferences),
      TranscriptRevision,
      PrefetchHooks Function({bool noteId, bool audioAssetId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NotesTableTableManager get notes =>
      $$NotesTableTableManager(_db, _db.notes);
  $$MediaAssetsTableTableManager get mediaAssets =>
      $$MediaAssetsTableTableManager(_db, _db.mediaAssets);
  $$AudioRecordingsTableTableManager get audioRecordings =>
      $$AudioRecordingsTableTableManager(_db, _db.audioRecordings);
  $$TranscriptRevisionsTableTableManager get transcriptRevisions =>
      $$TranscriptRevisionsTableTableManager(_db, _db.transcriptRevisions);
}
