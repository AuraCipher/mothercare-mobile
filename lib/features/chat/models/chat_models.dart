class ChatRoomSummary {
  const ChatRoomSummary({
    required this.id,
    required this.kind,
    required this.name,
    this.description,
    required this.canPost,
    required this.unreadCount,
    this.lastMessageAt,
    this.classGroupId,
  });

  final String id;
  final String kind;
  final String name;
  final String? description;
  final bool canPost;
  final int unreadCount;
  final DateTime? lastMessageAt;
  final String? classGroupId;

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
      classGroupId: json['classGroupId'] as String?,
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
        'classGroupId': classGroupId,
      };

  ChatRoomSummary copyWith({int? unreadCount}) {
    return ChatRoomSummary(
      id: id,
      kind: kind,
      name: name,
      description: description,
      canPost: canPost,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageAt: lastMessageAt,
      classGroupId: classGroupId,
    );
  }
}

class ChatLandingSection {
  const ChatLandingSection({
    required this.key,
    required this.title,
    this.rooms = const [],
    this.communities = const [],
    this.contacts = const [],
  });

  final String key;
  final String title;
  final List<ChatRoomSummary> rooms;
  final List<ChatClassCommunity> communities;
  final List<ChatContactSummary> contacts;

  factory ChatLandingSection.fromJson(Map<String, dynamic> json) {
    final roomsRaw = json['rooms'] as List<dynamic>? ?? [];
    final communitiesRaw = json['communities'] as List<dynamic>? ?? [];
    final contactsRaw = json['contacts'] as List<dynamic>? ?? [];
    return ChatLandingSection(
      key: json['key'] as String? ?? '',
      title: normalizeChatLabel(json['title'] as String? ?? ''),
      rooms: roomsRaw
          .map((e) => ChatRoomSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      communities: communitiesRaw
          .map((e) => ChatClassCommunity.fromJson(e as Map<String, dynamic>))
          .toList(),
      contacts: contactsRaw
          .map((e) => ChatContactSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'rooms': rooms.map((r) => r.toJson()).toList(),
        'communities': communities.map((c) => c.toJson()).toList(),
        'contacts': contacts.map((c) => c.toJson()).toList(),
      };

  ChatLandingSection copyWith({
    List<ChatRoomSummary>? rooms,
    List<ChatClassCommunity>? communities,
  }) {
    return ChatLandingSection(
      key: key,
      title: title,
      rooms: rooms ?? this.rooms,
      communities: communities ?? this.communities,
      contacts: contacts,
    );
  }
}

class ChatClassCommunity {
  const ChatClassCommunity({
    required this.groupId,
    required this.groupLabel,
    required this.displayOrder,
    required this.unreadCount,
    required this.rooms,
  });

  final String groupId;
  final String groupLabel;
  final int displayOrder;
  final int unreadCount;
  final List<ChatRoomSummary> rooms;

  factory ChatClassCommunity.fromJson(Map<String, dynamic> json) {
    final roomsRaw = json['rooms'] as List<dynamic>? ?? [];
    return ChatClassCommunity(
      groupId: json['groupId'] as String? ?? '',
      groupLabel: json['groupLabel'] as String? ?? '',
      displayOrder: json['displayOrder'] is int
          ? json['displayOrder'] as int
          : int.tryParse('${json['displayOrder']}') ?? 0,
      unreadCount: json['unreadCount'] is int
          ? json['unreadCount'] as int
          : int.tryParse('${json['unreadCount']}') ?? 0,
      rooms: roomsRaw
          .map((e) => ChatRoomSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'groupLabel': groupLabel,
        'displayOrder': displayOrder,
        'unreadCount': unreadCount,
        'rooms': rooms.map((r) => r.toJson()).toList(),
      };

  ChatClassCommunity copyWith({
    int? unreadCount,
    List<ChatRoomSummary>? rooms,
  }) {
    return ChatClassCommunity(
      groupId: groupId,
      groupLabel: groupLabel,
      displayOrder: displayOrder,
      unreadCount: unreadCount ?? this.unreadCount,
      rooms: rooms ?? this.rooms,
    );
  }

  ChatLandingSection toSection() {
    return ChatLandingSection(
      key: 'class-$groupId',
      title: groupLabel,
      rooms: rooms,
    );
  }
}

class ChatContactSummary {
  const ChatContactSummary({
    required this.userId,
    required this.name,
    required this.role,
    this.branchRole,
    this.dmRoomId,
    this.roleLabelOverride,
  });

  final String userId;
  final String name;
  final String role;
  final String? branchRole;
  final String? dmRoomId;
  final String? roleLabelOverride;

  factory ChatContactSummary.fromJson(Map<String, dynamic> json) {
    return ChatContactSummary(
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      role: json['role'] as String? ?? '',
      branchRole: json['branchRole'] as String?,
      dmRoomId: json['dmRoomId'] as String?,
      roleLabelOverride: json['roleLabel'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'name': name,
        'role': role,
        'branchRole': branchRole,
        'dmRoomId': dmRoomId,
        if (roleLabelOverride != null) 'roleLabel': roleLabelOverride,
      };

  String get roleLabel {
    if (roleLabelOverride != null && roleLabelOverride!.isNotEmpty) {
      return roleLabelOverride!;
    }
    switch (branchRole ?? role) {
      case 'branch_admin':
        return 'Principal';
      case 'sub_admin':
        return 'Admin';
      case 'teacher':
        return 'Teacher';
      case 'management':
        return 'Management';
      default:
        return role;
    }
  }
}

class ChatLandingData {
  const ChatLandingData({
    required this.sections,
    required this.rooms,
    this.communities = const [],
    this.contacts = const [],
  });

  final List<ChatLandingSection> sections;
  final List<ChatRoomSummary> rooms;
  final List<ChatClassCommunity> communities;
  final List<ChatContactSummary> contacts;

  factory ChatLandingData.fromJson(Map<String, dynamic> json) {
    final sectionsRaw = json['sections'] as List<dynamic>? ?? [];
    final roomsRaw = json['rooms'] as List<dynamic>? ?? [];
    final communitiesRaw = json['communities'] as List<dynamic>? ?? [];
    final contactsRaw = json['contacts'] as List<dynamic>? ?? [];
    return ChatLandingData(
      sections: sectionsRaw
          .map((e) => ChatLandingSection.fromJson(e as Map<String, dynamic>))
          .toList(),
      rooms: roomsRaw
          .map((e) => ChatRoomSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      communities: communitiesRaw
          .map((e) => ChatClassCommunity.fromJson(e as Map<String, dynamic>))
          .toList(),
      contacts: contactsRaw
          .map((e) => ChatContactSummary.fromJson(e as Map<String, dynamic>))
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
        'communities': communities.map((c) => c.toJson()).toList(),
        'contacts': contacts.map((c) => c.toJson()).toList(),
      };

  /// Clears unread badge for [roomId] across rooms, sections, and communities.
  ChatLandingData withRoomUnreadCleared(String roomId) {
    ChatRoomSummary patchRoom(ChatRoomSummary room) =>
        room.id == roomId ? room.copyWith(unreadCount: 0) : room;

    final nextRooms = rooms.map(patchRoom).toList();
    final nextCommunities = communities.map((community) {
      final nextCommunityRooms = community.rooms.map(patchRoom).toList();
      final unread = nextCommunityRooms.fold<int>(0, (sum, r) => sum + r.unreadCount);
      return community.copyWith(rooms: nextCommunityRooms, unreadCount: unread);
    }).toList();
    final nextSections = sections.map((section) {
      final nextSectionRooms = section.rooms.map(patchRoom).toList();
      final nextSectionCommunities = section.communities.map((community) {
        final nextCommunityRooms = community.rooms.map(patchRoom).toList();
        final unread = nextCommunityRooms.fold<int>(0, (sum, r) => sum + r.unreadCount);
        return community.copyWith(rooms: nextCommunityRooms, unreadCount: unread);
      }).toList();
      return section.copyWith(rooms: nextSectionRooms, communities: nextSectionCommunities);
    }).toList();

    return ChatLandingData(
      sections: nextSections,
      rooms: nextRooms,
      communities: nextCommunities,
      contacts: contacts,
    );
  }
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role,
      };
}

class ChatMessageMedia {
  const ChatMessageMedia({
    required this.id,
    required this.mimeType,
    required this.url,
    this.purpose,
  });

  final String id;
  final String mimeType;
  final String url;
  final String? purpose;

  factory ChatMessageMedia.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChatMessageMedia(id: '', mimeType: '', url: '');
    return ChatMessageMedia(
      id: json['id'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      url: json['publicUrl'] as String? ?? json['url'] as String? ?? '',
      purpose: json['purpose'] as String?,
    );
  }

  bool get hasContent => id.isNotEmpty && url.isNotEmpty;
  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo =>
      purpose != 'voice_note' && (mimeType.startsWith('video/') || purpose == 'video');
  bool get isAudio => mimeType.startsWith('audio/') || purpose == 'voice_note';
  bool get isDocument =>
      purpose == 'document' ||
      mimeType == 'application/pdf' ||
      mimeType.startsWith('application/') && !mimeType.startsWith('image/') && !mimeType.startsWith('video/');

  Map<String, dynamic> toJson() => {
        'id': id,
        'mimeType': mimeType,
        'publicUrl': url,
        'purpose': purpose,
      };
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
    this.mediaFile,
  });

  final String id;
  final String roomId;
  final String type;
  final String? title;
  final String? content;
  final ChatMessageSender sender;
  final DateTime createdAt;
  final bool isDeleted;
  final ChatMessageMedia? mediaFile;

  bool get isImageMessage => type == 'image' || mediaFile?.isImage == true;
  bool get isDocumentMessage => type == 'document' || mediaFile?.isDocument == true;
  bool get hasCaption => content != null && content!.trim().isNotEmpty;

  String get documentFileName {
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    final url = mediaFile?.url ?? '';
    if (url.isNotEmpty) {
      final segment = Uri.parse(url).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
      if (segment.isNotEmpty) return segment;
    }
    return 'Document';
  }

  String get displayText {
    if (isDeleted) return 'Message removed';
    if (content != null && content!.trim().isNotEmpty) return content!.trim();
    if (title != null && title!.trim().isNotEmpty) return title!.trim();
    if (mediaFile?.isImage == true) return 'Photo';
    if (mediaFile?.isVideo == true) return 'Video';
    if (mediaFile?.isAudio == true) return 'Voice message';
    if (type == 'image') return 'Photo';
    if (type == 'video') return 'Video';
    if (type == 'voice_note' || type == 'audio') return 'Voice message';
    if (type == 'document' || mediaFile?.isDocument == true) return documentFileName;
    return '';
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final created = json['createdAt'] as String? ?? '';
    final mediaRaw = json['mediaFile'] as Map<String, dynamic>?;
    return ChatMessage(
      id: json['id'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      title: json['title'] as String?,
      content: json['content'] as String?,
      sender: ChatMessageSender.fromJson(json['sender'] as Map<String, dynamic>? ?? {}),
      createdAt: DateTime.tryParse(created) ?? DateTime.now(),
      isDeleted: json['isDeleted'] as bool? ?? false,
      mediaFile: mediaRaw != null ? ChatMessageMedia.fromJson(mediaRaw) : null,
    );
  }

  factory ChatMessage.fromSocket(Map<String, dynamic> json) {
    final created = json['createdAt'] as String? ?? '';
    final mediaRaw = json['mediaFile'] as Map<String, dynamic>?;
    return ChatMessage(
      id: json['id'] as String? ?? '',
      roomId: json['roomId'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      title: json['title'] as String?,
      content: json['content'] as String?,
      sender: ChatMessageSender.fromJson(json['sender'] as Map<String, dynamic>? ?? {}),
      createdAt: DateTime.tryParse(created) ?? DateTime.now(),
      mediaFile: mediaRaw != null ? ChatMessageMedia.fromJson(mediaRaw) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'roomId': roomId,
        'type': type,
        'title': title,
        'content': content,
        'sender': sender.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'isDeleted': isDeleted,
        if (mediaFile != null) 'mediaFile': mediaFile!.toJson(),
      };

  ChatMessage copyWith({
    String? content,
    bool? isDeleted,
  }) {
    return ChatMessage(
      id: id,
      roomId: roomId,
      type: type,
      title: title,
      content: content ?? this.content,
      sender: sender,
      createdAt: createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      mediaFile: mediaFile,
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
  if (room.kind == 'system_attendance') return 'Attendance';
  if (room.kind == 'system_payment') return 'Fees & Payments';
  if (room.kind == 'system_result') return 'Results';
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

/// Contacts that must not appear as rows on chat landing (picker-only).
List<ChatContactSummary> landingVisibleContacts(
  List<ChatContactSummary> contacts,
  String currentUserId,
) {
  return contacts
      .where((c) => c.userId.isNotEmpty && c.userId != currentUserId && c.role != 'super_admin')
      .toList();
}

/// Hides self/CEO DM threads from landing lists; existing threads stay in picker/history.
List<ChatRoomSummary> landingVisibleDmRooms({
  required List<ChatRoomSummary> rooms,
  required String currentUserId,
  List<ChatContactSummary> contacts = const [],
}) {
  final hiddenDmRoomIds = <String>{
    for (final contact in contacts)
      if (contact.userId == currentUserId || contact.role == 'super_admin')
        if (contact.dmRoomId != null && contact.dmRoomId!.isNotEmpty) contact.dmRoomId!,
  };
  final hiddenNames = <String>{
    for (final contact in contacts)
      if (contact.userId == currentUserId || contact.role == 'super_admin')
        contact.name.trim().toLowerCase(),
  };

  return rooms.where((room) {
    if (room.kind != 'direct_message') return true;
    if (hiddenDmRoomIds.contains(room.id)) return false;
    if (hiddenNames.contains(room.name.trim().toLowerCase())) return false;
    return true;
  }).toList();
}

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
    ChatLandingSection(key: 'system', title: 'School Records', rooms: pick(['system_attendance', 'system_payment', 'system_result'])),
    ChatLandingSection(key: 'dm', title: 'Messages', rooms: pick(['direct_message'])),
  ].where((s) => s.rooms.isNotEmpty).toList();
}

class ContactPickerContact {
  const ContactPickerContact({
    required this.userId,
    required this.name,
    required this.roleLabel,
    this.subtitle,
    this.dmRoomId,
  });

  final String userId;
  final String name;
  final String roleLabel;
  final String? subtitle;
  final String? dmRoomId;

  factory ContactPickerContact.fromJson(Map<String, dynamic> json) {
    return ContactPickerContact(
      userId: json['userId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      roleLabel: json['roleLabel'] as String? ?? '',
      subtitle: json['subtitle'] as String?,
      dmRoomId: json['dmRoomId'] as String?,
    );
  }
}

class ContactPickerSection {
  const ContactPickerSection({
    required this.key,
    required this.title,
    required this.contacts,
  });

  final String key;
  final String title;
  final List<ContactPickerContact> contacts;

  factory ContactPickerSection.fromJson(Map<String, dynamic> json) {
    final raw = json['contacts'] as List<dynamic>? ?? [];
    return ContactPickerSection(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      contacts: raw.map((e) => ContactPickerContact.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ContactPickerClassGroup {
  const ContactPickerClassGroup({
    required this.groupId,
    required this.groupLabel,
    required this.contacts,
  });

  final String groupId;
  final String groupLabel;
  final List<ContactPickerContact> contacts;

  factory ContactPickerClassGroup.fromJson(Map<String, dynamic> json) {
    final raw = json['contacts'] as List<dynamic>? ?? [];
    return ContactPickerClassGroup(
      groupId: json['groupId'] as String? ?? '',
      groupLabel: json['groupLabel'] as String? ?? '',
      contacts: raw.map((e) => ContactPickerContact.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class ContactPickerData {
  const ContactPickerData({
    required this.sections,
    required this.classGroups,
  });

  final List<ContactPickerSection> sections;
  final List<ContactPickerClassGroup> classGroups;

  factory ContactPickerData.fromJson(Map<String, dynamic> json) {
    final sectionsRaw = json['sections'] as List<dynamic>? ?? [];
    final groupsRaw = json['classGroups'] as List<dynamic>? ?? [];
    return ContactPickerData(
      sections: sectionsRaw.map((e) => ContactPickerSection.fromJson(e as Map<String, dynamic>)).toList(),
      classGroups: groupsRaw.map((e) => ContactPickerClassGroup.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  ContactPickerData filteredForUser(String userId) {
    bool keep(ContactPickerContact c) => c.userId.isNotEmpty && c.userId != userId;
    return ContactPickerData(
      sections: sections
          .map(
            (s) => ContactPickerSection(
              key: s.key,
              title: s.title,
              contacts: s.contacts.where(keep).toList(),
            ),
          )
          .where((s) => s.contacts.isNotEmpty)
          .toList(),
      classGroups: classGroups
          .map(
            (g) => ContactPickerClassGroup(
              groupId: g.groupId,
              groupLabel: g.groupLabel,
              contacts: g.contacts.where(keep).toList(),
            ),
          )
          .where((g) => g.contacts.isNotEmpty)
          .toList(),
    );
  }
}
