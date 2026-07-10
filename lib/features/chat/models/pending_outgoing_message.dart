enum PendingSendPhase { uploading, sending, failed }

class PendingOutgoingMessage {
  const PendingOutgoingMessage({
    required this.localId,
    required this.type,
    this.content,
    this.previewLabel,
    this.localFilePath,
    this.progress = 0,
    this.phase = PendingSendPhase.uploading,
    this.fileName,
    this.purpose,
    this.durationSeconds,
    this.academicYearId,
  });

  final String localId;
  final String type;
  final String? content;
  final String? previewLabel;
  final String? localFilePath;
  final double progress;
  final PendingSendPhase phase;
  final String? fileName;
  final String? purpose;
  final String? durationSeconds;
  final String? academicYearId;

  bool get hasPersistableFile =>
      localFilePath != null &&
      localFilePath!.isNotEmpty &&
      type != 'text';

  PendingOutgoingMessage copyWith({
    double? progress,
    PendingSendPhase? phase,
    String? localFilePath,
    String? fileName,
    String? purpose,
    String? durationSeconds,
    String? academicYearId,
  }) {
    return PendingOutgoingMessage(
      localId: localId,
      type: type,
      content: content,
      previewLabel: previewLabel,
      localFilePath: localFilePath ?? this.localFilePath,
      progress: progress ?? this.progress,
      phase: phase ?? this.phase,
      fileName: fileName ?? this.fileName,
      purpose: purpose ?? this.purpose,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      academicYearId: academicYearId ?? this.academicYearId,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'type': type,
        'content': content,
        'previewLabel': previewLabel,
        'localFilePath': localFilePath,
        'progress': progress,
        'phase': phase.name,
        'fileName': fileName,
        'purpose': purpose,
        'durationSeconds': durationSeconds,
        'academicYearId': academicYearId,
      };

  factory PendingOutgoingMessage.fromJson(Map<String, dynamic> json) {
    final phaseName = json['phase'] as String? ?? PendingSendPhase.uploading.name;
    return PendingOutgoingMessage(
      localId: json['localId'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      content: json['content'] as String?,
      previewLabel: json['previewLabel'] as String?,
      localFilePath: json['localFilePath'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      phase: PendingSendPhase.values.firstWhere(
        (p) => p.name == phaseName,
        orElse: () => PendingSendPhase.failed,
      ),
      fileName: json['fileName'] as String?,
      purpose: json['purpose'] as String?,
      durationSeconds: json['durationSeconds'] as String?,
      academicYearId: json['academicYearId'] as String?,
    );
  }
}
