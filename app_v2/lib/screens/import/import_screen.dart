import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';

class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _urlController = TextEditingController();
  String? _detectedPlatform;
  bool _importing = false;
  final _stepStatuses = <String, bool>{
    'Downloading video': false,
    'Transcribing audio': false,
    'Extracting recipe': false,
    'Generating images': false,
  };
  Timer? _pollTimer;

  @override
  void dispose() {
    _urlController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _detectPlatform(String url) {
    setState(() {
      if (url.contains('tiktok')) {
        _detectedPlatform = 'tiktok';
      } else if (url.contains('youtube') || url.contains('youtu.be')) {
        _detectedPlatform = 'youtube';
      } else {
        _detectedPlatform = null;
      }
    });
  }

  Future<void> _startImport() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _importing = true);

    try {
      final apiClient = ref.read(apiClientProvider);
      final jobId = await apiClient.ingestUrl(url);
      _startPolling(jobId);
    } catch (e) {
      if (mounted) {
        setState(() => _importing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  void _startPolling(String jobId) {
    final steps = _stepStatuses.keys.toList();
    var currentStep = 0;

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final apiClient = ref.read(apiClientProvider);
        final job = await apiClient.getJob(jobId);

        if (!mounted) {
          timer.cancel();
          return;
        }

        // Map job status to step progress
        final status = job.status;
        if (status == 'downloading' || status == 'processing') {
          if (currentStep < steps.length) {
            setState(() {
              _stepStatuses[steps[currentStep]] = true;
              currentStep++;
            });
          }
        } else if (status == 'completed') {
          setState(() {
            for (final key in _stepStatuses.keys) {
              _stepStatuses[key] = true;
            }
          });
          timer.cancel();

          final recipeId = job.result?['recipe_id'] as String?;
          if (recipeId != null && mounted) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            if (mounted) context.go('/recipes/$recipeId/edit');
          }
        } else if (status == 'failed') {
          timer.cancel();
          if (mounted) {
            setState(() => _importing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Import failed')),
            );
          }
        }
      } catch (_) {
        // Polling error, will retry next tick
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: const Text(
          'Import Recipe',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // URL Field
            TextField(
              controller: _urlController,
              autofocus: true,
              enabled: !_importing,
              onChanged: _detectPlatform,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: const InputDecoration(
                hintText: 'Paste a TikTok or YouTube link',
              ),
            ),
            const SizedBox(height: 12),

            // Platform detection
            if (_detectedPlatform != null) _buildPlatformBadge(),

            const SizedBox(height: 20),

            // Import button
            if (!_importing)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _urlController.text.trim().isEmpty
                      ? null
                      : _startImport,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Import Recipe',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // Progress steps
            if (_importing) ...[
              const SizedBox(height: 8),
              ..._stepStatuses.entries.map((entry) {
                return _buildProgressStep(entry.key, entry.value);
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformBadge() {
    final isTikTok = _detectedPlatform == 'tiktok';
    final text =
        isTikTok ? '\u{1F4F1} TikTok recipe detected' : '\u25B6\uFE0F YouTube video detected';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.green.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.green,
        ),
      ),
    );
  }

  Widget _buildProgressStep(String label, bool completed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            completed ? '\u2705' : '\u23F3',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: completed
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}
