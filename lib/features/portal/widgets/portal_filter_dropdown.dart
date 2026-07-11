import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class PortalFilterDropdown extends StatelessWidget {
  const PortalFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.includeAll = true,
  });

  final String label;
  final String value;
  final List<PortalFilterOption> options;
  final ValueChanged<String> onChanged;
  final bool includeAll;

  @override
  Widget build(BuildContext context) {
    final items = <DropdownMenuItem<String>>[
      if (includeAll) const DropdownMenuItem(value: 'all', child: Text('All')),
      ...options.map(
        (opt) => DropdownMenuItem(
          value: opt.id,
          child: Text(opt.label, overflow: TextOverflow.ellipsis),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: items.any((item) => item.value == value) ? value : items.first.value,
              items: items,
              onChanged: (next) {
                if (next != null) onChanged(next);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class PortalFilterOption {
  const PortalFilterOption({required this.id, required this.label});

  final String id;
  final String label;
}
