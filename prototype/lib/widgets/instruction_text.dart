import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/instruction.dart';
import '../models/cooking_session.dart';
import '../utils/temperature_converter.dart';

/// Widget that renders instruction text with highlighted ingredients, equipment, and temperatures.
/// Parses placeholders like {i:key}, {i:key:qty}, {e:key}, {temp:400F} and renders them with
/// distinct styling.
class InstructionText extends StatelessWidget {
  final String template;
  final InstructionStep? step;
  final SessionStep? sessionStep;
  final TextStyle? baseStyle;
  final TextAlign textAlign;
  final Color ingredientColor;
  final Color equipmentColor;
  final Color temperatureColor;
  final double paxMultiplier;
  final String unitSystem;

  const InstructionText({
    super.key,
    required this.template,
    this.step,
    this.sessionStep,
    this.baseStyle,
    this.textAlign = TextAlign.start,
    this.ingredientColor = const Color(0xFFF4A460), // Sandy brown / warm orange
    this.equipmentColor = const Color(0xFF87CEEB), // Sky blue
    this.temperatureColor = const Color(0xFFFF6B6B), // Coral red (hot!)
    this.paxMultiplier = 1.0,
    this.unitSystem = 'metric',
  });

  /// Creates an InstructionText from an InstructionStep
  factory InstructionText.fromStep(
    InstructionStep step, {
    TextStyle? baseStyle,
    TextAlign textAlign = TextAlign.start,
    Color ingredientColor = const Color(0xFFF4A460),
    Color equipmentColor = const Color(0xFF87CEEB),
    Color temperatureColor = const Color(0xFFFF6B6B),
    double paxMultiplier = 1.0,
    String unitSystem = 'metric',
  }) {
    return InstructionText(
      template: step.detailedDescription,
      step: step,
      baseStyle: baseStyle,
      textAlign: textAlign,
      ingredientColor: ingredientColor,
      equipmentColor: equipmentColor,
      temperatureColor: temperatureColor,
      paxMultiplier: paxMultiplier,
      unitSystem: unitSystem,
    );
  }

  /// Creates an InstructionText from a SessionStep
  factory InstructionText.fromSessionStep(
    SessionStep sessionStep, {
    TextStyle? baseStyle,
    TextAlign textAlign = TextAlign.start,
    Color ingredientColor = const Color(0xFFF4A460),
    Color equipmentColor = const Color(0xFF87CEEB),
    Color temperatureColor = const Color(0xFFFF6B6B),
    String unitSystem = 'metric',
  }) {
    return InstructionText(
      template: sessionStep.detailedDescription,
      sessionStep: sessionStep,
      baseStyle: baseStyle,
      textAlign: textAlign,
      ingredientColor: ingredientColor,
      equipmentColor: equipmentColor,
      temperatureColor: temperatureColor,
      unitSystem: unitSystem,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = baseStyle ?? GoogleFonts.lato(fontSize: 16, color: Colors.black87, height: 1.6);
    final spans = _parseTemplate(style);

    return Text.rich(
      TextSpan(
        style: style,
        children: spans,
      ),
      textAlign: textAlign,
    );
  }

  List<InlineSpan> _parseTemplate(TextStyle baseStyle) {
    final spans = <InlineSpan>[];

    // Build lookup maps from step or session step
    final ingredientMap = _buildIngredientMap();
    final equipmentMap = _buildEquipmentMap();

    // Regex to find all placeholders: {i:key}, {i:key:qty}, {e:key}, {temp:400F}, {temp:200C}
    final pattern = RegExp(r'\{(i|e|temp):([^}]+?)(?::qty)?\}');
    var lastEnd = 0;

    for (final match in pattern.allMatches(template)) {
      // Add any text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: template.substring(lastEnd, match.start)));
      }

      final type = match.group(1)!; // 'i', 'e', or 'temp'
      final value = match.group(2)!;
      final isQuantity = match.group(0)!.contains(':qty');

      if (type == 'i') {
        // Ingredient placeholder
        final ingredient = ingredientMap[value];
        if (ingredient != null) {
          final text = (isQuantity ? ingredient['qty_display'] : ingredient['name']) ?? '';
          final imageUrl = ingredient['image_url'];
          
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _HoverableText(
              text: text,
              imageUrl: imageUrl,
              style: baseStyle.copyWith(
                color: ingredientColor,
                fontWeight: FontWeight.w600,
                backgroundColor: ingredientColor.withValues(alpha: 0.15),
              ),
            ),
          ));
        } else {
          // Placeholder not found - render as-is
          spans.add(TextSpan(text: match.group(0)));
        }
      } else if (type == 'e') {
        // Equipment placeholder
        final equipment = equipmentMap[value];
        if (equipment != null) {
          final imageUrl = equipment['image_url'];
          
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _HoverableText(
              text: equipment['name'] ?? '',
              imageUrl: imageUrl,
              style: baseStyle.copyWith(
                color: equipmentColor,
                fontWeight: FontWeight.w600,
                backgroundColor: equipmentColor.withValues(alpha: 0.15),
              ),
            ),
          ));
        } else {
          // Placeholder not found - render as-is
          spans.add(TextSpan(text: match.group(0)));
        }
      } else if (type == 'temp') {
        // Temperature placeholder - convert if needed
        final convertedTemp = TemperatureConverter.convertTemperaturesInText(
          value,
          unitSystem,
        );

        spans.add(TextSpan(
          text: convertedTemp,
          style: baseStyle.copyWith(
            color: temperatureColor,
            fontWeight: FontWeight.w600,
            backgroundColor: temperatureColor.withValues(alpha: 0.15),
          ),
        ));
      }

      lastEnd = match.end;
    }

    // Add remaining text after last match
    if (lastEnd < template.length) {
      spans.add(TextSpan(text: template.substring(lastEnd)));
    }

    return spans;
  }

  Map<String, Map<String, String?>> _buildIngredientMap() {
    final map = <String, Map<String, String?>>{};

    if (sessionStep != null) {
      for (final ing in sessionStep!.stepIngredients) {
        map[ing.placeholderKey] = {
          'name': ing.master.name,
          'qty_display': ing.quantityDisplay,
          'image_url': ing.master.imageUrl,
        };
      }
    } else if (step != null) {
      for (final ing in step!.stepIngredients) {
        // Apply pax multiplier to get scaled display
        final scaledIng = ing.scaled(paxMultiplier);
        map[ing.placeholderKey] = {
          'name': ing.master.name,
          'qty_display': scaledIng.quantityDisplay,
          'image_url': ing.master.imageUrl,
        };
      }
    }

    return map;
  }

  Map<String, Map<String, String?>> _buildEquipmentMap() {
    final map = <String, Map<String, String?>>{};

    if (sessionStep != null) {
      for (final eq in sessionStep!.stepEquipment) {
        map[eq.placeholderKey] = {
          'name': eq.master.name,
          'image_url': eq.master.imageUrl,
        };
      }
    } else if (step != null) {
      for (final eq in step!.stepEquipment) {
        map[eq.placeholderKey] = {
          'name': eq.master.name,
          'image_url': eq.master.imageUrl,
        };
      }
    }

    return map;
  }
}

/// A simple text widget that shows the interpolated description without highlighting.
/// Useful for voice agent or plain text display.
class InterpolatedInstructionText extends StatelessWidget {
  final InstructionStep? step;
  final SessionStep? sessionStep;
  final TextStyle? style;
  final TextAlign textAlign;
  final double paxMultiplier;

  const InterpolatedInstructionText({
    super.key,
    this.step,
    this.sessionStep,
    this.style,
    this.textAlign = TextAlign.start,
    this.paxMultiplier = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    String text;
    if (sessionStep != null) {
      text = sessionStep!.interpolatedDescription;
    } else if (step != null) {
      final scaledStep = step!.scaled(paxMultiplier);
      text = scaledStep.interpolatedDescription;
    } else {
      text = '';
    }

    return Text(
      text,
      style: style ?? GoogleFonts.lato(fontSize: 16, color: Colors.black87, height: 1.6),
      textAlign: textAlign,
    );
  }
}

/// Hoverable text widget that shows an image preview on hover
class _HoverableText extends StatefulWidget {
  final String text;
  final String? imageUrl;
  final TextStyle style;

  const _HoverableText({
    required this.text,
    required this.imageUrl,
    required this.style,
  });

  @override
  State<_HoverableText> createState() => _HoverableTextState();
}

class _HoverableTextState extends State<_HoverableText> {
  bool _isHovering = false;
  OverlayEntry? _overlayEntry;

  void _showOverlay(BuildContext context) {
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty) {
      print('No image URL for: ${widget.text}');
      return;
    }

    print('Showing overlay for: ${widget.text} with URL: ${widget.imageUrl}');

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      print('RenderBox is null');
      return;
    }

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // Calculate position to keep overlay on screen
    double left = offset.dx;
    double top = offset.dy + size.height + 8;

    // Adjust if overlay would go off right edge
    if (left + 200 > screenSize.width) {
      left = screenSize.width - 210;
    }

    // Adjust if overlay would go off bottom edge
    if (top + 200 > screenSize.height) {
      top = offset.dy - 208; // Show above instead
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              widget.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
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
      cursor: widget.imageUrl != null && widget.imageUrl!.isNotEmpty 
        ? SystemMouseCursors.click 
        : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.imageUrl != null && widget.imageUrl!.isNotEmpty
          ? () {
              print('Tapped: ${widget.text}');
              if (_overlayEntry == null) {
                _showOverlay(context);
              } else {
                _hideOverlay();
              }
            }
          : null,
        child: Text(
          widget.text,
          style: widget.style.copyWith(
            decoration: _isHovering && widget.imageUrl != null && widget.imageUrl!.isNotEmpty
              ? TextDecoration.underline 
              : null,
          ),
        ),
      ),
    );
  }
}
