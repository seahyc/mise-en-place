import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/cooking_session.dart';
import '../utils/temperature_converter.dart';
import 'dart:math' as math;

/// Represents a pending text change for streaming animation.
class TextChangeAnimation {
  final String stepId;
  final String oldText;
  final String newText;
  final DateTime timestamp;

  const TextChangeAnimation({
    required this.stepId,
    required this.oldText,
    required this.newText,
    required this.timestamp,
  });

  /// Compute the diff between old and new text.
  /// Returns (commonPrefix, removedPart, addedPart, commonSuffix)
  TextDiff computeDiff() {
    // Find longest common prefix
    int prefixEnd = 0;
    final minLen = math.min(oldText.length, newText.length);
    while (prefixEnd < minLen && oldText[prefixEnd] == newText[prefixEnd]) {
      prefixEnd++;
    }

    // Find longest common suffix (from end, not overlapping with prefix)
    int oldSuffixStart = oldText.length;
    int newSuffixStart = newText.length;
    while (oldSuffixStart > prefixEnd &&
        newSuffixStart > prefixEnd &&
        oldText[oldSuffixStart - 1] == newText[newSuffixStart - 1]) {
      oldSuffixStart--;
      newSuffixStart--;
    }

    return TextDiff(
      commonPrefix: oldText.substring(0, prefixEnd),
      removedPart: oldText.substring(prefixEnd, oldSuffixStart),
      addedPart: newText.substring(prefixEnd, newSuffixStart),
      commonSuffix: oldText.substring(oldSuffixStart),
    );
  }
}

/// Result of comparing old and new text.
class TextDiff {
  final String commonPrefix;
  final String removedPart;
  final String addedPart;
  final String commonSuffix;

  const TextDiff({
    required this.commonPrefix,
    required this.removedPart,
    required this.addedPart,
    required this.commonSuffix,
  });

  bool get hasChanges => removedPart.isNotEmpty || addedPart.isNotEmpty;

  @override
  String toString() =>
      'TextDiff(prefix: "$commonPrefix", removed: "$removedPart", added: "$addedPart", suffix: "$commonSuffix")';
}

/// Widget that animates changes to instruction text.
///
/// When the text changes:
/// 1. Unchanged prefix and suffix remain stable
/// 2. Removed text fades out with strikethrough
/// 3. New text "types in" character by character with a glow effect
class StreamingInstructionText extends StatefulWidget {
  final SessionStep step;
  final String oldDescription;
  final TextStyle? baseStyle;
  final TextAlign textAlign;
  final Color ingredientColor;
  final Color equipmentColor;
  final Color temperatureColor;
  final String unitSystem;

  const StreamingInstructionText({
    super.key,
    required this.step,
    required this.oldDescription,
    this.baseStyle,
    this.textAlign = TextAlign.start,
    this.ingredientColor = const Color(0xFFF4A460),
    this.equipmentColor = const Color(0xFF87CEEB),
    this.temperatureColor = const Color(0xFFFF6B6B),
    this.unitSystem = 'metric',
  });

  @override
  State<StreamingInstructionText> createState() =>
      _StreamingInstructionTextState();
}

class _StreamingInstructionTextState extends State<StreamingInstructionText>
    with TickerProviderStateMixin {
  late AnimationController _fadeOutController;
  late AnimationController _typeInController;
  late Animation<double> _fadeOutAnimation;
  late Animation<double> _typeInAnimation;

  late TextDiff _diff;
  int _visibleCharCount = 0;
  bool _fadeOutComplete = false;

  @override
  void initState() {
    super.initState();

    // Compute diff between old and new
    final change = TextChangeAnimation(
      stepId: widget.step.id,
      oldText: widget.oldDescription,
      newText: widget.step.detailedDescription,
      timestamp: DateTime.now(),
    );
    _diff = change.computeDiff();
    debugPrint('[StreamingText] Diff: $_diff');

    // Fade out removed text (300ms)
    _fadeOutController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeOutController, curve: Curves.easeOut),
    );
    _fadeOutController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _fadeOutComplete = true);
        _startTypeIn();
      }
    });

    // Type in new text (variable duration based on length)
    final typeInDuration = Duration(
      milliseconds: math.max(300, _diff.addedPart.length * 30),
    );
    _typeInController = AnimationController(
      duration: typeInDuration,
      vsync: this,
    );
    _typeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _typeInController, curve: Curves.easeOut),
    );
    _typeInController.addListener(() {
      final newCount = (_typeInAnimation.value * _diff.addedPart.length).round();
      if (newCount != _visibleCharCount) {
        setState(() => _visibleCharCount = newCount);
      }
    });

    // Start animation sequence
    if (_diff.removedPart.isNotEmpty) {
      _fadeOutController.forward();
    } else {
      _fadeOutComplete = true;
      _startTypeIn();
    }
  }

  void _startTypeIn() {
    if (_diff.addedPart.isNotEmpty) {
      _typeInController.forward();
    }
  }

  @override
  void dispose() {
    _fadeOutController.dispose();
    _typeInController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.baseStyle ??
        GoogleFonts.lato(fontSize: 16, color: Colors.black87, height: 1.6);

    return AnimatedBuilder(
      animation: Listenable.merge([_fadeOutController, _typeInController]),
      builder: (context, _) {
        final spans = _buildAnimatedSpans(style);
        return Text.rich(
          TextSpan(style: style, children: spans),
          textAlign: widget.textAlign,
        );
      },
    );
  }

  List<InlineSpan> _buildAnimatedSpans(TextStyle baseStyle) {
    final spans = <InlineSpan>[];

    // 1. Common prefix (parse for placeholders)
    if (_diff.commonPrefix.isNotEmpty) {
      spans.addAll(_parseSegment(_diff.commonPrefix, baseStyle));
    }

    // 2. Removed part (fade out with strikethrough)
    if (_diff.removedPart.isNotEmpty && !_fadeOutComplete) {
      final opacity = _fadeOutAnimation.value;
      spans.add(TextSpan(
        text: _diff.removedPart,
        style: baseStyle.copyWith(
          color: baseStyle.color?.withValues(alpha: opacity * 0.7),
          decoration: TextDecoration.lineThrough,
          decorationColor: Colors.red.withValues(alpha: opacity),
        ),
      ));
    }

    // 3. Added part (type in with glow)
    if (_diff.addedPart.isNotEmpty && _fadeOutComplete) {
      final visibleText = _diff.addedPart.substring(0, _visibleCharCount);
      final hiddenText = _diff.addedPart.substring(_visibleCharCount);

      if (visibleText.isNotEmpty) {
        // The visible typed-in text with subtle glow on last few chars
        final isTyping = _visibleCharCount < _diff.addedPart.length;
        spans.addAll(_parseSegment(
          visibleText,
          baseStyle,
          isNewText: true,
          showGlow: isTyping,
        ));
      }

      if (hiddenText.isNotEmpty) {
        // Invisible placeholder to maintain layout stability
        spans.add(TextSpan(
          text: hiddenText,
          style: baseStyle.copyWith(color: Colors.transparent),
        ));
      }
    }

    // 4. Common suffix (parse for placeholders)
    if (_diff.commonSuffix.isNotEmpty) {
      spans.addAll(_parseSegment(_diff.commonSuffix, baseStyle));
    }

    return spans;
  }

  /// Parse a text segment for ingredient/equipment/temperature placeholders.
  List<InlineSpan> _parseSegment(
    String text,
    TextStyle baseStyle, {
    bool isNewText = false,
    bool showGlow = false,
  }) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\{(i|e|temp):([^}]+?)(?::qty)?\}');
    var lastEnd = 0;

    // Build lookup maps
    final ingredientMap = _buildIngredientMap();
    final equipmentMap = _buildEquipmentMap();

    for (final match in pattern.allMatches(text)) {
      // Text before match
      if (match.start > lastEnd) {
        final plainText = text.substring(lastEnd, match.start);
        spans.add(_styledTextSpan(plainText, baseStyle, isNewText, showGlow));
      }

      final type = match.group(1)!;
      final value = match.group(2)!;
      final isQuantity = match.group(0)!.contains(':qty');

      TextStyle highlightStyle;
      String displayText;

      if (type == 'i') {
        final ing = ingredientMap[value];
        displayText = ing != null
            ? (isQuantity ? ing['qty_display'] : ing['name']) ?? ''
            : match.group(0)!;
        highlightStyle = baseStyle.copyWith(
          color: widget.ingredientColor,
          fontWeight: FontWeight.w600,
          backgroundColor: widget.ingredientColor.withValues(alpha: 0.15),
        );
      } else if (type == 'e') {
        final eq = equipmentMap[value];
        displayText = eq?['name'] ?? match.group(0)!;
        highlightStyle = baseStyle.copyWith(
          color: widget.equipmentColor,
          fontWeight: FontWeight.w600,
          backgroundColor: widget.equipmentColor.withValues(alpha: 0.15),
        );
      } else if (type == 'temp') {
        displayText = TemperatureConverter.convertTemperaturesInText(
          value,
          widget.unitSystem,
        );
        highlightStyle = baseStyle.copyWith(
          color: widget.temperatureColor,
          fontWeight: FontWeight.w600,
          backgroundColor: widget.temperatureColor.withValues(alpha: 0.15),
        );
      } else {
        displayText = match.group(0)!;
        highlightStyle = baseStyle;
      }

      if (isNewText && showGlow) {
        highlightStyle = highlightStyle.copyWith(
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: 0.8),
              blurRadius: 8,
            ),
          ],
        );
      }

      spans.add(TextSpan(text: displayText, style: highlightStyle));
      lastEnd = match.end;
    }

    // Remaining text
    if (lastEnd < text.length) {
      final plainText = text.substring(lastEnd);
      spans.add(_styledTextSpan(plainText, baseStyle, isNewText, showGlow));
    }

    return spans;
  }

  TextSpan _styledTextSpan(
    String text,
    TextStyle baseStyle,
    bool isNewText,
    bool showGlow,
  ) {
    if (isNewText && showGlow) {
      // Add subtle glow to newly typed text
      return TextSpan(
        text: text,
        style: baseStyle.copyWith(
          shadows: [
            Shadow(
              color: Colors.white.withValues(alpha: 0.6),
              blurRadius: 4,
            ),
          ],
        ),
      );
    }
    return TextSpan(text: text, style: baseStyle);
  }

  Map<String, Map<String, String?>> _buildIngredientMap() {
    final map = <String, Map<String, String?>>{};
    for (final ing in widget.step.stepIngredients) {
      map[ing.placeholderKey] = {
        'name': ing.master.name,
        'qty_display': ing.quantityDisplay,
        'image_url': ing.master.imageUrl,
      };
    }
    return map;
  }

  Map<String, Map<String, String?>> _buildEquipmentMap() {
    final map = <String, Map<String, String?>>{};
    for (final eq in widget.step.stepEquipment) {
      map[eq.placeholderKey] = {
        'name': eq.master.name,
        'image_url': eq.master.imageUrl,
      };
    }
    return map;
  }
}
