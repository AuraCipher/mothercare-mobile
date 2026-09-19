import '../../features/chat/models/chat_models.dart';

/// M9: resolve a push-tap `roomId` to its authoritative room (kind + name)
/// from cached landing data — stable identifiers instead of display-name
/// heuristics. Returns null when the room is not in the cache (caller falls
/// back to heuristics or a generic room screen).
ChatRoomSummary? findCachedPushRoom(ChatLandingData landing, String roomId) {
  for (final room in landing.rooms) {
    if (room.id == roomId) return room;
  }
  for (final section in landing.sections) {
    for (final room in section.rooms) {
      if (room.id == roomId) return room;
    }
    for (final community in section.communities) {
      for (final room in community.rooms) {
        if (room.id == roomId) return room;
      }
    }
  }
  for (final community in landing.communities) {
    for (final room in community.rooms) {
      if (room.id == roomId) return room;
    }
  }
  return null;
}
