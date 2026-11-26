enum AgentStepType {
  info,
  user,
  assistant,
  toolCall,
  toolResult,
  error,
  done,
}

class AgentStep {
  final DateTime timestamp;
  final AgentStepType type;
  final String title;
  final String detail;
  final bool isScreenAction;

  AgentStep({
    DateTime? timestamp,
    required this.type,
    required this.title,
    this.detail = '',
    this.isScreenAction = false,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AgentMessage {
  final String role; // user, assistant, tool
  final String content;
  final List<Map<String, dynamic>>? toolCalls;
  final String? toolCallId;
  final String? name;

  AgentMessage({
    required this.role,
    required this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
      'content': content,
    };
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls;
    }
    if (toolCallId != null) {
      map['tool_call_id'] = toolCallId;
    }
    if (name != null) {
      map['name'] = name;
    }
    return map;
  }
}
