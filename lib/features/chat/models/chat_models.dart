class ChatRoomSummary {
  const ChatRoomSummary({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    required this.canPost,
    required this.unreadCount,
    this.lastMessageAt,
  });

  final String id;
  final String kind;
  final String name;
  final String? description;
  final bool canPost;
  final int unreadCount;
  final DateTime? lastMessageAt;

  factory ChatRoomSummary.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessageAt'] as String?;
    return ChatRoomSummary(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      name: normalizeChatLabel(json['name'] as String? ?? ''),
      description: json['description'] as String?,
      canPost: json['canPost'] as bool? ?? false,
      unreadCount: json['unreadCount'] is int
          ? json['unreadCount'] as int
          : int.tryParse('${json['unreadCount']}') ?? 0,
      lastMessageAt: last != null ? DateTime.tryParse(last) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'description': description,
        'canPost': canPost,
        'unreadCount': unreadCount,
        'lastMessageAt': lastMessageAt?.toUtc().toIso8601String(),
      };
}

class ChatLandingSection {
  const ChatLandingSection({
    required this.key,
    required this.title,
    required this.rooms,
  });

  final String key;
  final String title;
  final List<ChatRoomSummary> rooms;

  factory ChatLandingSection.fromJson(Map<String, dynamic> json) {
    final roomsRaw = json['rooms'] as List<dynamic>? ?? [];
    return ChatLandingSection(
      key: json['key'] as String? ?? '',
      title: normalizeChatLabel(json['title'] as String? ?? ''),
      rooms: roomsRaw
          .map((e) => ChatRoomSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };
}

class ChatLandingData {
  const ChatLandingData({
    required this.sections,
    required this.rooms,
  });

  final List<ChatLandingSection> sections;
  final List<ChatRoomSummary> rooms;

  factory ChatLandingData.fromJson(Map<String, dynamic> json) {
    final sectionsRaw = json['sections'] as List<dynamic>? ?? [];
    final roomsRaw = json['rooms'] as List<dynamic>? ?? [];
    return ChatLandingData(
      sections: sectionsRaw
          .map((e) => ChatLandingSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      rooms: roomsRaw
          .map((e) => ChatRoomSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  ChatRoomSummary? roomById(String id) {
    for (final room in rooms) {
      if (room.id == id) return room;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'sections': sections.map((s) => s.toJson()).toList(),
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };
}

class ChatMessageSender {
  const ChatMessageSender({
    required this.id,
    required this.name,
    required this.role,
  });

  final String id;
  final String name;
  final String role;

  factory ChatMessageSender.fromJson(Map<String, dynamic> json) {
    return ChatMessageSender(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.type,
    this.title,
    this.content,
    required this.sender,
    required this.createdAt,
    this.isDeleted = false,
  });

  final String id;
  final String roomId;
  final String type;
  final String? title;
  final String? content;
  final ChatMessageSender sender;
  final DateTime createdAt;
  final bool isDeleted;

  String get displayText {
    if (isDeleted) return 'Message removed';
    if (content != null && content!.trim().isNotEmpty) return content!.trim();
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    return '';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      title: json['title'] as String?,
      content: json['content'] as String?,
      sender: ChatMessageSender.fromJson(json['sender'] as Map<String, dynamic>? ?? {}),
      createdAt: DateTime.tryParse(created) ?? DateTime.now(),
      isDeleted: json['isDeleted'] as bool? ?? false,
    );
  }

  factory ChatMessage.fromSocket(Map<String, dynamic> json) {
    final created = json['createdAt'] as String? ?? '';
    return ChatMessage(
      id: json['id'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      title: json['title'] as String?,
      content: json['content'] as String?,
      sender: ChatMessageSender.fromJson(json['sender'] as Map<String, dynamic>? ?? {}),
      createdAt: DateTime.tryParse(created) ?? DateTime.now(),
    );
  }
}

/// Maps legacy backend labels to current copy.
String normalizeChatLabel(String value) {
  if (value == 'Whole School') return 'School Announcement';
  return value;
}

/// Student's class name from bootstrap, e.g. "Playgroup" or "Class 8 — CS".
String classDisplayName(String? groupLabel) {
  final label = groupLabel?.trim();
  if (label != null && label.isNotEmpty) return label;
  return 'My Class';
}

String displayRoomName(ChatRoomSummary room, {String? groupLabel}) {
  if (room.kind == 'school_announcement') return 'Announcement';
  if (room.kind == 'class_announcement') return 'Class Announcement';
  return room.name;
}

String displaySectionTitle(ChatLandingSection section, {String? groupLabel}) {
  if (section.key == 'class') return classCommunityTitle(groupLabel);
  return section.title;
}

/// e.g. "Playgroup Community" from backend `groupLabel`.
String classCommunityTitle(String? groupLabel) {
  final label = groupLabel?.trim();
  if (label != null && label.isNotEmpty) return '$label Community';
  return 'Class Community';
}

List<ChatRoomSummary> classAnnouncementRooms(ChatLandingSection section) =>
    section.rooms.where((r) => r.kind == 'class_announcement').toList();

List<ChatRoomSummary> classGroupRooms(ChatLandingSection section) =>
    section.rooms.where((r) => r.kind == 'group_chat').toList();

int classCommunityUnread(ChatLandingSection section) =>
    section.rooms.fold<int>(0, (sum, r) => sum + r.unreadCount);

List<ChatLandingSection> groupRoomsForStaffLanding(List<ChatRoomSummary> rooms) {
  List<ChatRoomSummary> pick(List<String> kinds) =>
      rooms.where((r) => kinds.contains(r.kind)).toList();

  return [
    ChatLandingSection(key: 'school', title: 'School Announcement', rooms: pick(['school_announcement'])),
    ChatLandingSection(
      key: 'channels',
      title: 'My Channels',
      rooms: pick(['class_announcement', 'group_chat']),
    ),
    ChatLandingSection(key: 'system', title: 'Updates', rooms: pick(['system_attendance', 'system_payment'])),
    ChatLandingSection(key: 'dm', title: 'Messages', rooms: pick(['direct_message'])),
  ].where((s) => s.rooms.isNotEmpty).toList();
}
