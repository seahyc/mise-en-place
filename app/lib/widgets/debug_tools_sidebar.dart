import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Debug log entry for ElevenLabs events
class DebugLogEntry {
  final DateTime timestamp;
  final String type; // 'user', 'agent', 'tool', 'system', 'error'
  final String message;
  final Map<String, dynamic>? metadata;

  DebugLogEntry({
    required this.type,
    required this.message,
    this.metadata,
  }) : timestamp = DateTime.now();
}

/// A compact debug panel positioned at bottom-right corner.
class DebugToolsSidebar extends StatefulWidget {
  final Map<String, Function> tools;
  final VoidCallback onClose;
  final List<DebugLogEntry> logEntries;
  final String? conversationId;
  final String connectionStatus;
  final bool agentSpeaking;
  final bool userSpeaking;
  final double vadScore;
  final String? lastUserTranscript;
  final String? lastAgentResponse;
  final int activeTimers;

  const DebugToolsSidebar({
    super.key,
    required this.tools,
    required this.onClose,
    this.logEntries = const [],
    this.conversationId,
    this.connectionStatus = 'disconnected',
    this.agentSpeaking = false,
    this.userSpeaking = false,
    this.vadScore = 0.0,
    this.lastUserTranscript,
    this.lastAgentResponse,
    this.activeTimers = 0,
  });

  @override
  State<DebugToolsSidebar> createState() => _DebugToolsSidebarState();
}

class _DebugToolsSidebarState extends State<DebugToolsSidebar> {
  String? _selectedTool;
  final Map<String, TextEditingController> _paramControllers = {};
  String? _result;
  bool _isLoading = false;

  // Tool parameter definitions
  static const Map<String, List<ToolParam>> _toolParams = {
    'get_cooking_state': [],
    'get_current_step_details': [],
    'get_full_recipe_details': [],
    'navigate_to_step': [
      ToolParam('step_index', 'Step Index', 'number', '0'),
    ],
    'mark_step_complete': [
      ToolParam('step_index', 'Step Index', 'number', '0'),
    ],
    'manage_timer': [
      ToolParam('action', 'Action', 'dropdown', 'set', ['set', 'update', 'get', 'dismiss']),
      ToolParam('duration_seconds', 'Duration (for set)', 'number', '60'),
      ToolParam('label', 'Label (for set/find)', 'text', 'Timer'),
      ToolParam('new_label', 'New Label (for update)', 'text', ''),
      ToolParam('emoji', 'Emoji (optional)', 'text', ''),
      ToolParam('timer_id', 'Timer ID (for update/get/dismiss)', 'text', ''),
      ToolParam('add_seconds', 'Add Time (for update)', 'number', ''),
      ToolParam('subtract_seconds', 'Subtract Time (for update)', 'number', ''),
      ToolParam('notify_at_seconds', 'Milestones (e.g. [30,10])', 'text', ''),
    ],
    'switch_units': [
      ToolParam('unit_system', 'Unit System', 'dropdown', 'metric', ['metric', 'imperial']),
    ],
    'modify_instructions': [
      ToolParam('changes', 'Changes (JSON)', 'text', '{}'),
    ],
  };

  @override
  void dispose() {
    for (var controller in _paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onToolSelected(String? toolName) {
    setState(() {
      _selectedTool = toolName;
      _result = null;

      // Clear old controllers
      for (var controller in _paramControllers.values) {
        controller.dispose();
      }
      _paramControllers.clear();

      // Create new controllers for this tool's parameters
      if (toolName != null) {
        final params = _toolParams[toolName] ?? [];
        for (var param in params) {
          _paramControllers[param.name] = TextEditingController(text: param.defaultValue);
        }
      }
    });
  }

  Future<void> _executeTool() async {
    if (_selectedTool == null) return;

    print('[DebugSidebar] _executeTool called for: $_selectedTool');

    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final tool = widget.tools[_selectedTool];
      if (tool == null) {
        print('[DebugSidebar] Tool not found: $_selectedTool');
        setState(() => _result = 'Tool not found');
        return;
      }

      // Build params from controllers
      final params = <String, dynamic>{};
      final toolParamDefs = _toolParams[_selectedTool] ?? [];

      for (var paramDef in toolParamDefs) {
        final controller = _paramControllers[paramDef.name];
        if (controller != null && controller.text.isNotEmpty) {
          // Parse based on type
          if (paramDef.type == 'number') {
            params[paramDef.name] = num.tryParse(controller.text) ?? controller.text;
          } else {
            params[paramDef.name] = controller.text;
          }
        }
      }

      print('[DebugSidebar] Executing $_selectedTool with params: $params');

      // Execute tool - always pass params map (tools that don't need params will ignore it)
      // Note: Some tools take no params, some take Map<String, dynamic>
      // We try with params first, then without if that fails
      dynamic result;
      try {
        result = await Function.apply(tool, [params]);
      } catch (e) {
        print('[DebugSidebar] First attempt failed: $e');
        // Tool doesn't accept params, try calling without
        if (e.toString().contains('positional arguments')) {
          result = await Function.apply(tool, []);
        } else {
          rethrow;
        }
      }

      print('[DebugSidebar] Tool result: $result');

      setState(() {
        _result = const JsonEncoder.withIndent('  ').convert(result);
      });
    } catch (e, stack) {
      print('[DebugSidebar] Error executing tool: $e');
      print('[DebugSidebar] Stack trace: $stack');
      setState(() => _result = 'Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Track which tab is selected: 0 = logs, 1 = tools
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      height: 350,
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildHeader(),
          _buildStatusBar(),
          _buildTabBar(),
          Expanded(
            child: _tabIndex == 0 ? _buildLogsTab() : _buildToolsTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    final isConnected = widget.connectionStatus == 'connected';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Connection status
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.connectionStatus,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 12),
          // Agent/User speaking indicators
          Text(
            'Agent: ${widget.agentSpeaking ? "🗣️" : "—"}',
            style: GoogleFonts.jetBrainsMono(
              color: widget.agentSpeaking ? const Color(0xFFFFB74D) : Colors.white38,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'User: ${widget.userSpeaking ? "🎤" : "—"}',
            style: GoogleFonts.jetBrainsMono(
              color: widget.userSpeaking ? const Color(0xFF64B5F6) : Colors.white38,
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'VAD: ${widget.vadScore.toStringAsFixed(2)}',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
          const Spacer(),
          Text(
            'Timers: ${widget.activeTimers}',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          _buildTab('Logs', 0),
          _buildTab('Tools', 1),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.orange : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.lato(
              color: isSelected ? Colors.orange : Colors.white54,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogsTab() {
    if (widget.logEntries.isEmpty) {
      return Center(
        child: Text(
          'No logs yet...\nStart talking to see transcripts',
          textAlign: TextAlign.center,
          style: GoogleFonts.lato(
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.logEntries.length,
      reverse: true, // Latest at bottom
      itemBuilder: (context, index) {
        final entry = widget.logEntries[widget.logEntries.length - 1 - index];
        return _buildLogEntry(entry);
      },
    );
  }

  Widget _buildLogEntry(DebugLogEntry entry) {
    Color typeColor;
    String prefix;
    switch (entry.type) {
      case 'user':
        typeColor = const Color(0xFF64B5F6);
        prefix = '👤';
      case 'agent':
        typeColor = const Color(0xFFFFB74D);
        prefix = '🤖';
      case 'tool':
        typeColor = const Color(0xFF81C784);
        prefix = '🔧';
      case 'error':
        typeColor = Colors.red;
        prefix = '❌';
      default:
        typeColor = Colors.white54;
        prefix = '📋';
    }

    final time = '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white38,
              fontSize: 9,
            ),
          ),
          const SizedBox(width: 6),
          Text(prefix, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              entry.message,
              style: GoogleFonts.jetBrainsMono(
                color: typeColor,
                fontSize: 10,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolSelector(),
          if (_selectedTool != null) _buildDynamicParamsInput(),
          _buildExecuteButton(),
          if (_result != null) _buildCompactResult(),
        ],
      ),
    );
  }

  Widget _buildCompactResult() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      constraints: const BoxConstraints(maxHeight: 100),
      child: SingleChildScrollView(
        child: Text(
          _result!,
          style: GoogleFonts.jetBrainsMono(
            color: Colors.green,
            fontSize: 9,
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bug_report, color: Colors.orange, size: 16),
          const SizedBox(width: 6),
          Text(
            'Debug Panel',
            style: GoogleFonts.jetBrainsMono(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (widget.conversationId != null)
            Text(
              widget.conversationId!.substring(0, 8),
              style: GoogleFonts.jetBrainsMono(
                color: Colors.white38,
                fontSize: 9,
              ),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onClose,
            child: const Icon(Icons.close, color: Colors.white54, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButton<String>(
        value: _selectedTool,
        hint: Text(
          'Select tool...',
          style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 11),
        ),
        isExpanded: true,
        dropdownColor: const Color(0xFF2a2a2a),
        underline: const SizedBox(),
        isDense: true,
        items: widget.tools.keys.map((name) {
          return DropdownMenuItem(
            value: name,
            child: Text(
              name,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
            ),
          );
        }).toList(),
        onChanged: _onToolSelected,
      ),
    );
  }

  Widget _buildDynamicParamsInput() {
    final toolParamDefs = _toolParams[_selectedTool] ?? [];

    if (toolParamDefs.isEmpty) {
      return Text(
        'No parameters needed',
        style: GoogleFonts.lato(
          color: Colors.white38,
          fontSize: 10,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: toolParamDefs.map((param) => _buildParamField(param)).toList(),
    );
  }

  Widget _buildParamField(ToolParam param) {
    final controller = _paramControllers[param.name];
    if (controller == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            param.label,
            style: GoogleFonts.lato(
              color: Colors.white54,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          if (param.type == 'dropdown' && param.options != null)
            _buildDropdownField(param, controller)
          else
            _buildTextField(param, controller),
        ],
      ),
    );
  }

  Widget _buildDropdownField(ToolParam param, TextEditingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButton<String>(
        value: controller.text.isNotEmpty ? controller.text : param.options!.first,
        isExpanded: true,
        dropdownColor: const Color(0xFF2a2a2a),
        underline: const SizedBox(),
        isDense: true,
        items: param.options!.map((option) {
          return DropdownMenuItem(
            value: option,
            child: Text(
              option,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 10),
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            controller.text = value;
          }
        },
      ),
    );
  }

  Widget _buildTextField(ToolParam param, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 10),
      keyboardType: param.type == 'number' ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        hintText: param.defaultValue,
        hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 10),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.orange),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        isDense: true,
      ),
    );
  }

  Widget _buildExecuteButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _selectedTool == null || _isLoading ? null : _executeTool,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Execute', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ),
    );
  }
}

/// Parameter definition for a tool
class ToolParam {
  final String name;
  final String label;
  final String type; // 'text', 'number', 'dropdown'
  final String defaultValue;
  final List<String>? options; // For dropdown type

  const ToolParam(
    this.name,
    this.label,
    this.type,
    this.defaultValue, [
    this.options,
  ]);
}
