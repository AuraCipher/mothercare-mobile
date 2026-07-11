import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/universal_header.dart';
import '../models/chat_models.dart';

typedef ContactPickerOpenRoom = Future<void> Function(ContactPickerContact contact);

/// Sectioned contact picker — WhatsApp-style new message screen.
class ChatContactPickerScreen extends StatefulWidget {
  const ChatContactPickerScreen({
    super.key,
    required this.currentUserId,
    required this.fetchContacts,
    required this.openRoom,
    this.title = 'New message',
  });

  final String currentUserId;
  final Future<ContactPickerData> Function() fetchContacts;
  final ContactPickerOpenRoom openRoom;
  final String title;

  @override
  State<ChatContactPickerScreen> createState() => _ChatContactPickerScreenState();
}

class _ChatContactPickerScreenState extends State<ChatContactPickerScreen> {
  ContactPickerData? _data;
  bool _loading = true;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.fetchContacts();
      if (!mounted) return;
      setState(() {
        _data = data.filteredForUser(widget.currentUserId);
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load contacts';
        _loading = false;
      });
    }
  }

  bool _matches(ContactPickerContact c) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return c.name.toLowerCase().contains(q) ||
        (c.subtitle?.toLowerCase().contains(q) ?? false) ||
        c.roleLabel.toLowerCase().contains(q);
  }

  Future<void> _pick(ContactPickerContact contact) async {
    await widget.openRoom(contact);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UniversalHeader(title: widget.title, showBack: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search contacts',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.violet));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.error)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final data = _data!;
    final children = <Widget>[];

    for (final section in data.sections) {
      final contacts = section.contacts.where(_matches).toList();
      if (contacts.isEmpty) continue;
      children.add(_sectionTitle(section.title));
      children.addAll(contacts.map(_contactTile));
    }

    for (final group in data.classGroups) {
      final contacts = group.contacts.where(_matches).toList();
      if (contacts.isEmpty) continue;
      children.add(_sectionTitle(group.groupLabel));
      children.addAll(contacts.map(_contactTile));
    }

    if (children.isEmpty) {
      return const Center(child: Text('No contacts found', style: TextStyle(color: AppColors.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: children,
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textMuted,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _contactTile(ContactPickerContact contact) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _pick(contact),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.violet.withValues(alpha: 0.12),
                child: Text(
                  contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(contact.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      contact.subtitle ?? contact.roleLabel,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
