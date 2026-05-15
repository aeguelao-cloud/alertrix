import 'package:flutter/material.dart';

import '../models/monitoring_models.dart';

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.item,
    this.onTap,
  });

  final AlertEvent item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: item.severity.color.withOpacity(0.12),
          child: Icon(
            Icons.notification_important_outlined,
            color: item.severity.color,
            size: 18,
          ),
        ),
        title: Text(item.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(item.zone),
        trailing: Text(
          _formatTime(item.timestamp),
          style: const TextStyle(
            color: Color(0xFF708189),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
