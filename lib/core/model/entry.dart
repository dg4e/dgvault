import 'attachment.dart';
import 'field.dart';

/// A credential record. Mirrors the KDBX entry model: standard + custom fields,
/// tags, icon, attachments, and a bounded history of prior versions.
class Entry {
  Entry({
    required this.uuid,
    Map<String, Field>? fields,
    List<String>? tags,
    List<Attachment>? attachments,
    List<Entry>? history,
    this.iconId = 0,
    this.customIconUuid,
    this.created,
    this.modified,
  })  : fields = fields ?? <String, Field>{},
        tags = tags ?? <String>[],
        attachments = attachments ?? <Attachment>[],
        history = history ?? <Entry>[];

  /// Stable 128-bit identifier (KDBX UUID, base64).
  final String uuid;

  /// Field map keyed by field name (see [Field] standard keys).
  final Map<String, Field> fields;

  /// KeePass tags.
  final List<String> tags;

  final List<Attachment> attachments;

  /// Prior versions, oldest-first. Pushed on every save (Entry History feature).
  final List<Entry> history;

  /// Preset icon index, or 0 when a [customIconUuid] is used.
  int iconId;

  /// Reference into the database custom-icon pool, when set.
  String? customIconUuid;

  DateTime? created;
  DateTime? modified;

  String? get title => fields[Field.title]?.value.reveal();
}
