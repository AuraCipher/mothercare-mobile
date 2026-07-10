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
  });

  final String localId;
  final String type;
  final String? content;
  final String? previewLabel;
  final String? localFilePath;
  final double progress;
  final PendingSendPhase phase;

  PendingOutgoingMessage copyWith({
    double? progress,
    PendingSendPhase? phase,
  }) {
    return PendingOutgoingMessage(
      localId: localId,
      type: type,
      content: content,
      previewLabel: previewLabel,
      localFilePath: localFilePath,
      progress: progress ?? this.progress,
      phase: phase ?? this.phase,
    );
  }
}
