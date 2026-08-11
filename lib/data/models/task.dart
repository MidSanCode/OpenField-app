/// A single built-in achievable reward definition returned by the server.
class Task {
  final int id;
  final String code;
  final String kind;
  final String name;
  final String description;
  final int rewardExp;
  final int rewardCurrency;
  final int target;
  final int sort;

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
  final Task task;
  final int progress;
  final bool completed;
  final bool claimable;

  const TaskState({
    required this.task,
    required this.progress,
    required this.completed,
    required this.claimable,
  });

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
  final int id;
  final int amount;
  final String reason;
  final String description;
  final DateTime createdAt;

  const ExpEntry({
    required this.id,
    required this.amount,
    required this.reason,
    required this.description,
    required this.createdAt,
  });

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