import 'enums.dart';
import 'ingredient.dart';
import 'equipment.dart';

/// A runtime cooking session - independent copy of recipe instructions
/// that can be modified by the voice agent without affecting the original recipe.
class CookingSession {
  final String id;
  final String? userId;
  final SessionStatus status;
  final double paxMultiplier;
  final int currentStepIndex;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final List<String> sourceRecipeIds;
  final List<SessionStep> steps;

  const CookingSession({
    required this.id,
    this.userId,
    this.status = SessionStatus.setup,
    this.paxMultiplier = 1.0,
    this.currentStepIndex = 0,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
    this.sourceRecipeIds = const [],
    this.steps = const [],
  });

  /// Creates a copy with updated fields.
  CookingSession copyWith({
    String? id,
    String? userId,
    SessionStatus? status,
    double? paxMultiplier,
    int? currentStepIndex,
    DateTime? startedAt,
    DateTime? completedAt,
    DateTime? createdAt,
    List<String>? sourceRecipeIds,
    List<SessionStep>? steps,
  }) {
    return CookingSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      paxMultiplier: paxMultiplier ?? this.paxMultiplier,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      sourceRecipeIds: sourceRecipeIds ?? this.sourceRecipeIds,
      steps: steps ?? this.steps,
    );
  }

  /// Current step being executed.
  SessionStep? get currentStep =>
      currentStepIndex >= 0 && currentStepIndex < steps.length
          ? steps[currentStepIndex]
          : null;

  /// All completed steps.
  List<SessionStep> get completedSteps =>
      steps.where((s) => s.isCompleted).toList();

  /// All pending (not completed, not skipped) steps.
  List<SessionStep> get pendingSteps =>
      steps.where((s) => !s.isCompleted && !s.isSkipped).toList();

  /// Progress as percentage (0.0 to 1.0).
  double get progress =>
      steps.isEmpty ? 0.0 : completedSteps.length / steps.length;

  factory CookingSession.fromJson(Map<String, dynamic> json) {
    return CookingSession(
      id: json['id'],
      userId: json['user_id'],
      status: _parseSessionStatus(json['status']),
      paxMultiplier: (json['pax_multiplier'] as num?)?.toDouble() ?? 1.0,
      currentStepIndex: json['current_step_index'] ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'])
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      sourceRecipeIds: (json['source_recipe_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      steps: (json['session_steps'] as List<dynamic>?)
              ?.map((s) => SessionStep.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  static SessionStatus _parseSessionStatus(String? value) {
    switch (value) {
      case 'setup':
        return SessionStatus.setup;
      case 'in_progress':
        return SessionStatus.inProgress;
      case 'paused':
        return SessionStatus.paused;
      case 'completed':
        return SessionStatus.completed;
      case 'abandoned':
        return SessionStatus.abandoned;
      default:
        return SessionStatus.setup;
    }
  }
}

/// A mutable copy of an instruction step within a cooking session.
/// Can be modified by the voice agent (e.g., adjust amounts, add notes).
class SessionStep {
  final String id;
  final String sessionId;
  final String? sourceStepId;
  final int orderIndex;
  final String shortText;
  final String detailedDescription; // Template with placeholders
  final String? mediaUrl;
  final bool isCompleted;
  final DateTime? completedAt;
  final bool isSkipped;
  final String? agentNotes;
  final List<SessionStepIngredient> stepIngredients;
  final List<SessionStepEquipment> stepEquipment;

  const SessionStep({
    required this.id,
    required this.sessionId,
    this.sourceStepId,
    required this.orderIndex,
    required this.shortText,
    required this.detailedDescription,
    this.mediaUrl,
    this.isCompleted = false,
    this.completedAt,
    this.isSkipped = false,
    this.agentNotes,
    this.stepIngredients = const [],
    this.stepEquipment = const [],
  });

  /// Interpolates placeholders in detailedDescription with actual values.
  /// Uses adjusted amounts from session ingredients.
  String get interpolatedDescription {
    return interpolateTemplate(detailedDescription);
  }

  /// Interpolates a template string with this step's ingredients and equipment.
  String interpolateTemplate(String template) {
    var result = template;

    // Build lookup maps
    final ingredientMap = {for (var i in stepIngredients) i.placeholderKey: i};
    final equipmentMap = {for (var e in stepEquipment) e.placeholderKey: e};

    // Replace {i:key:qty} first (more specific)
    result = result.replaceAllMapped(
      RegExp(r'\{i:(\w+):qty\}'),
      (match) {
        final key = match.group(1)!;
        final ing = ingredientMap[key];
        return ing?.quantityDisplay ?? match.group(0)!;
      },
    );

    // Replace {i:key} (ingredient name only)
    result = result.replaceAllMapped(
      RegExp(r'\{i:(\w+)\}'),
      (match) {
        final key = match.group(1)!;
        final ing = ingredientMap[key];
        return ing?.master.name ?? match.group(0)!;
      },
    );

    // Replace {e:key} (equipment name)
    result = result.replaceAllMapped(
      RegExp(r'\{e:(\w+)\}'),
      (match) {
        final key = match.group(1)!;
        final equip = equipmentMap[key];
        return equip?.master.name ?? match.group(0)!;
      },
    );

    return result;
  }

  /// Creates a copy with updated fields.
  SessionStep copyWith({
    String? id,
    String? sessionId,
    String? sourceStepId,
    int? orderIndex,
    String? shortText,
    String? detailedDescription,
    String? mediaUrl,
    bool? isCompleted,
    DateTime? completedAt,
    bool? isSkipped,
    String? agentNotes,
    List<SessionStepIngredient>? stepIngredients,
    List<SessionStepEquipment>? stepEquipment,
  }) {
    return SessionStep(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      sourceStepId: sourceStepId ?? this.sourceStepId,
      orderIndex: orderIndex ?? this.orderIndex,
      shortText: shortText ?? this.shortText,
      detailedDescription: detailedDescription ?? this.detailedDescription,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: completedAt ?? this.completedAt,
      isSkipped: isSkipped ?? this.isSkipped,
      agentNotes: agentNotes ?? this.agentNotes,
      stepIngredients: stepIngredients ?? this.stepIngredients,
      stepEquipment: stepEquipment ?? this.stepEquipment,
    );
  }

  factory SessionStep.fromJson(Map<String, dynamic> json) {
    return SessionStep(
      id: json['id'],
      sessionId: json['session_id'] ?? '',
      sourceStepId: json['source_step_id'],
      orderIndex: json['order_index'] ?? 0,
      shortText: json['short_text'] ?? '',
      detailedDescription: json['detailed_description'] ?? '',
      mediaUrl: json['media_url'],
      isCompleted: json['is_completed'] ?? false,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'])
          : null,
      isSkipped: json['is_skipped'] ?? false,
      agentNotes: json['agent_notes'],
      stepIngredients: (json['session_step_ingredients'] as List<dynamic>?)
              ?.map((i) =>
                  SessionStepIngredient.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      stepEquipment: (json['session_step_equipment'] as List<dynamic>?)
              ?.map(
                  (e) => SessionStepEquipment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Ingredient within a session step - can track original vs adjusted amounts,
/// substitutions, and modifications made by the voice agent.
class SessionStepIngredient {
  final String id;
  final String sessionStepId;
  final IngredientMaster master;
  final double? originalAmount;
  final double? adjustedAmount;
  final String? unit;
  final String placeholderKey;
  final bool isSubstitution;
  final String? substitutionNote;

  const SessionStepIngredient({
    required this.id,
    required this.sessionStepId,
    required this.master,
    this.originalAmount,
    this.adjustedAmount,
    this.unit,
    required this.placeholderKey,
    this.isSubstitution = false,
    this.substitutionNote,
  });

  /// The effective amount to use (adjusted if available, otherwise original).
  double? get effectiveAmount => adjustedAmount ?? originalAmount;

  /// Formats as "amount unit name" for {i:key:qty} placeholder.
  String get quantityDisplay {
    final amount = effectiveAmount;
    if (amount == null || unit == null) return master.name;
    final formattedAmount =
        amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(1);
    return '$formattedAmount $unit ${master.name}';
  }

  /// Creates a copy with updated fields.
  SessionStepIngredient copyWith({
    String? id,
    String? sessionStepId,
    IngredientMaster? master,
    double? originalAmount,
    double? adjustedAmount,
    String? unit,
    String? placeholderKey,
    bool? isSubstitution,
    String? substitutionNote,
  }) {
    return SessionStepIngredient(
      id: id ?? this.id,
      sessionStepId: sessionStepId ?? this.sessionStepId,
      master: master ?? this.master,
      originalAmount: originalAmount ?? this.originalAmount,
      adjustedAmount: adjustedAmount ?? this.adjustedAmount,
      unit: unit ?? this.unit,
      placeholderKey: placeholderKey ?? this.placeholderKey,
      isSubstitution: isSubstitution ?? this.isSubstitution,
      substitutionNote: substitutionNote ?? this.substitutionNote,
    );
  }

  factory SessionStepIngredient.fromJson(Map<String, dynamic> json) {
    return SessionStepIngredient(
      id: json['id'] ?? '',
      sessionStepId: json['session_step_id'] ?? '',
      master: IngredientMaster.fromJson(
          json['ingredient_master'] ?? json['master'] ?? {}),
      originalAmount: (json['original_amount'] as num?)?.toDouble(),
      adjustedAmount: (json['adjusted_amount'] as num?)?.toDouble(),
      unit: json['unit_master']?['abbreviation'] ??
          json['unit_master']?['name'] ??
          json['unit'],
      placeholderKey: json['placeholder_key'] ?? '',
      isSubstitution: json['is_substitution'] ?? false,
      substitutionNote: json['substitution_note'],
    );
  }
}

/// Equipment within a session step - can track substitutions.
class SessionStepEquipment {
  final String id;
  final String sessionStepId;
  final EquipmentMaster master;
  final String placeholderKey;
  final bool isSubstitution;
  final String? substitutionNote;

  const SessionStepEquipment({
    required this.id,
    required this.sessionStepId,
    required this.master,
    required this.placeholderKey,
    this.isSubstitution = false,
    this.substitutionNote,
  });

  /// Creates a copy with updated fields.
  SessionStepEquipment copyWith({
    String? id,
    String? sessionStepId,
    EquipmentMaster? master,
    String? placeholderKey,
    bool? isSubstitution,
    String? substitutionNote,
  }) {
    return SessionStepEquipment(
      id: id ?? this.id,
      sessionStepId: sessionStepId ?? this.sessionStepId,
      master: master ?? this.master,
      placeholderKey: placeholderKey ?? this.placeholderKey,
      isSubstitution: isSubstitution ?? this.isSubstitution,
      substitutionNote: substitutionNote ?? this.substitutionNote,
    );
  }

  factory SessionStepEquipment.fromJson(Map<String, dynamic> json) {
    return SessionStepEquipment(
      id: json['id'] ?? '',
      sessionStepId: json['session_step_id'] ?? '',
      master: EquipmentMaster.fromJson(
          json['equipment_master'] ?? json['master'] ?? {}),
      placeholderKey: json['placeholder_key'] ?? '',
      isSubstitution: json['is_substitution'] ?? false,
      substitutionNote: json['substitution_note'],
    );
  }
}
