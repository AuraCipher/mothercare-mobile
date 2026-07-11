import 'package:flutter/material.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/offline_banner.dart';

class PortalPanelScaffold extends StatelessWidget {
  const PortalPanelScaffold({
    super.key,
    required this.loading,
    required this.offline,
    this.error,
    this.onRetry,
    required this.child,
  });

  final bool loading;
  final bool offline;
  final String? error;
  final VoidCallback? onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (offline) const OfflineBanner(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 13))),
                  if (onRetry != null)
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.violet))
              : child,
        ),
      ],
    );
  }
}

Future<void> runPortalLoad<T>({
  required Future<T> Function() fetch,
  required Future<T?> Function() readCache,
  required Future<void> Function(T data) saveCache,
  required void Function(T data, {required bool offline}) onData,
  required void Function(String message, {required bool offline}) onError,
  required void Function({required bool loading}) onLoading,
}) async {
  onLoading(loading: true);
  T? cached;
  try {
    cached = await readCache();
    if (cached != null) {
      onData(cached, offline: false);
      onLoading(loading: false);
    }
  } catch (_) {}

  try {
    final fresh = await fetch();
    await saveCache(fresh);
    onData(fresh, offline: false);
    onError('', offline: false);
  } on ApiException catch (e) {
    if (cached != null) {
      onData(cached, offline: true);
      onError('', offline: true);
    } else {
      onError(e.message, offline: true);
    }
  } catch (_) {
    if (cached != null) {
      onData(cached, offline: true);
      onError('', offline: true);
    } else {
      onError('Could not load data. Check your connection.', offline: true);
    }
  } finally {
    onLoading(loading: false);
  }
}
