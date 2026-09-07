/// A single built-in achievable reward definition returned by the server.
class Task {
  /// Server-assigned task id.
  final int id;
  /// Stable machine identifier of the task (used by the server to track
  /// progress across requests).
  final String code;
  /// Task cadence: 'once' for one-off tasks, 'streak' for daily-streak tasks
  /// (see [isStreak]).
  final String kind;
  /// Display name of the task.
  final String name;
  /// Human-readable description of what to do.
  final String description;
  /// Experience awarded when the reward is claimed.
  final int rewardExp;
  /// Coins awarded when the reward is claimed.
  final int rewardCurrency;
  /// Progress value the user must reach to complete the task.
  final int target;
  /// Display ordering hint from the server.
  final int sort;

  /// Creates a task; see [fromJson] for payload defaults.
  const Task({
    required this.id,
    required this.code,
    required this.kind,
    required this.name,
    required this.description,
    required this.rewardExp,
    required this.rewardCurrency,
    required this.target,
    required this.sort,
  });

  /// Deserializes from the server's task payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: _asInt(json['id']),
      code: json['code'] as String? ?? '',
      kind: json['kind'] as String? ?? 'once',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      rewardExp: _asInt(json['reward_exp']),
      rewardCurrency: _asInt(json['reward_currency']),
      target: _asInt(json['target']),
      sort: _asInt(json['sort']),
    );
  }

  /// True for daily-streak tasks (kind == 'streak').
  bool get isStreak => kind == 'streak';

  static int _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// A [Task] enriched with the requesting user's progress and claimability.
class TaskState {
  /// The task definition the state belongs to.
  final Task task;
  /// The user's current progress toward [Task.target].
  final int progress;
  /// Whether the task has been completed.
  final bool completed;
  /// Whether the reward can be claimed right now (server-decided).
  final bool claimable;

  /// Creates a task state; see [fromJson] for payload defaults.
  const TaskState({
    required this.task,
    required this.progress,
    required this.completed,
    required this.claimable,
  });

  /// Deserializes from the server's task-state payload; the embedded task
  /// fields are parsed by [Task.fromJson] from the same object.
  factory TaskState.fromJson(Map<String, dynamic> json) {
    return TaskState(
      task: Task.fromJson(json),
      progress: Task._asInt(json['progress']),
      completed: json['completed'] as bool? ?? false,
      claimable: json['claimable'] as bool? ?? false,
    );
  }
}

/// One recorded experience award in the user's history.
class ExpEntry {
  /// Server-assigned history entry id.
  final int id;
  /// Experience awarded by this entry.
  final int amount;
  /// Machine-readable cause of the award (e.g. a task code).
  final String reason;
  /// Human-readable description of the award.
  final String description;
  /// When the award happened (localized timestamp).
  final DateTime createdAt;

  /// Creates a history entry; see [fromJson] for payload defaults.
  const ExpEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.description,
    required this.createdAt,
  });

  /// Deserializes from the server's history payload; unparseable dates fall
  /// back to the Unix epoch.
  factory ExpEntry.fromJson(Map<String, dynamic> json) {
    return ExpEntry(
      id: Task._asInt(json['id']),
      amount: Task._asInt(json['amount']),
      reason: json['reason'] as String? ?? '',
      description: json['description'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}