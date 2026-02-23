import 'package:flutter/material.dart';

void main() {
  runApp(const TestHoverApp());
}

class TestHoverApp extends StatelessWidget {
  const TestHoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Hover over the text below:'),
              const SizedBox(height: 20),
              HoverableTestWidget(
                text: 'Onion',
                imageUrl: 'https://images.unsplash.com/photo-1508747703725-719777637510?auto=format&fit=crop&w=500&q=80',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HoverableTestWidget extends StatefulWidget {
  final String text;
  final String imageUrl;

  const HoverableTestWidget({
    super.key,
    required this.text,
    required this.imageUrl,
  });

  @override
  State<HoverableTestWidget> createState() => _HoverableTestWidgetState();
}

class _HoverableTestWidgetState extends State<HoverableTestWidget> {
  bool _isHovering = false;
  OverlayEntry? _overlayEntry;

  void _showOverlay(BuildContext context) {
    print('Showing overlay for: ${widget.text}');

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      print('RenderBox is null');
      return;
    }

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 8,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.red),
              ),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    print('Hiding overlay');
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        print('Mouse entered: ${widget.text}');
        setState(() => _isHovering = true);
        _showOverlay(context);
      },
      onExit: (_) {
        print('Mouse exited: ${widget.text}');
        setState(() => _isHovering = false);
        _hideOverlay();
      },
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          widget.text,
          style: TextStyle(
            color: Colors.orange.shade700,
            fontWeight: FontWeight.w600,
            decoration: _isHovering ? TextDecoration.underline : null,
          ),
        ),
      ),
    );
  }
}
