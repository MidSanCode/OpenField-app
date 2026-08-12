import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/models/task.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/account/checkin_calendar_page.dart';

/// The in-app task center: daily sign-in, streak milestones and one-time
/// achievements with claimable EXP and currency rewards.
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final ApiService _apiService = ApiService();
  List<TaskState> _tasks = const [];
  int _streak = 0;
  int _makeupCost = 0;
  bool _isLoading = true;
  String? _error;
  String? _claimingCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _apiService.listTasks(token);
      if (!mounted) return;
      final list = data['tasks'];
      setState(() {
        _tasks = list is List
            ? list
                .whereType<Map<String, dynamic>>()
                .map((e) => TaskState.fromJson(e))
                .toList()
            : const [];
        _streak = (data['streak'] as num?)?.toInt() ?? 0;
        _makeupCost = (data['makeup_cost'] as num?)?.toInt() ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _load();
    if (!mounted) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.fetchCurrentUser();
  }

  Future<void> _claim(TaskState state) async {
    if (_claimingCode != null) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _claimingCode = state.task.code);
    try {
      if (state.task.code == 'daily_login') {
        await _apiService.claimDailyLogin(token);
      } else {
        await _apiService.claimTask(token, state.task.code);
      }
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('taskClaimedReward'.tr(namedArgs: {
            'exp': '${state.task.rewardExp}',
            'currency': '${state.task.rewardCurrency}',
          })),
        ),
      );
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _claimingCode = null);
    }
  }

  Future<void> _openCalendar() async {
    if (_claimingCode != null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CheckinCalendarPage()),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('tasks'.tr())),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('loadFailed'.tr()),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text('retry'.tr())),
          ],
        ),
      );
    }
    final daily = _tasks
        .where((t) => t.task.code == 'daily_login')
        .firstOrNull;
    final milestones = _tasks
        .where((t) => t.task.kind == 'streak' && t.task.code != 'daily_login')
        .toList();
    final onceTasks =
        _tasks.where((t) => t.task.kind == 'once').toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (daily != null) ...[
            _buildDailyCard(context, daily),
            const SizedBox(height: 16),
          ],
          if (milestones.isNotEmpty) ...[
            _sectionTitle('taskMilestones'.tr()),
            ...milestones.map((t) => _buildTaskTile(context, t)),
            const SizedBox(height: 8),
          ],
          if (onceTasks.isNotEmpty) ...[
            _sectionTitle('taskAchievements'.tr()),
            ...onceTasks.map((t) => _buildTaskTile(context, t)),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDailyCard(BuildContext context, TaskState daily) {
    final theme = Theme.of(context);
    final canClaim = daily.claimable;
    final busy = _claimingCode != null;
    final isBusyDaily = _claimingCode == 'daily_login';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.local_fire_department,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    daily.task.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  'taskStreakDays'.tr(namedArgs: {'streak': '$_streak'}),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              daily.task.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _RewardChips(task: daily.task),
                const Spacer(),
                if (daily.completed)
                  const Icon(Icons.check_circle, color: Colors.green)
                else
                  FilledButton.icon(
                    onPressed:
                        canClaim && !busy ? () => _claim(daily) : null,
                    icon: isBusyDaily
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt, size: 18),
                    label: Text('taskClaim'.tr()),
                  ),
              ],
            ),
            if (!daily.completed) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : _openCalendar,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: Text('taskMakeupCost'.tr(namedArgs: {'cost': '$_makeupCost'})),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskTile(BuildContext context, TaskState state) {
    final theme = Theme.of(context);
    final task = state.task;
    final busy = _claimingCode != null;
    final isBusyThis = _claimingCode == task.code;
    final progress = state.progress;
    final target = task.target;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  task.kind == 'streak'
                      ? Icons.local_fire_department
                      : Icons.emoji_events_outlined,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.name, style: theme.textTheme.titleSmall),
                ),
                if (state.completed)
                  const Icon(Icons.check_circle, color: Colors.green)
                else
                  FilledButton.tonal(
                    onPressed:
                        state.claimable && !busy ? () => _claim(state) : null,
                    child: isBusyThis
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('taskClaim'.tr()),
                  ),
              ],
            ),
            if (task.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                task.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: target > 0
                          ? (progress / target).clamp(0.0, 1.0)
                          : 0,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'taskProgress'.tr(
                    namedArgs: {'progress': '$progress', 'target': '$target'},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _RewardChips(task: task),
          ],
        ),
      ),
    );
  }
}

class _RewardChips extends StatelessWidget {
  final Task task;

  const _RewardChips({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    if (task.rewardExp > 0) {
      widgets.add(_chip(context, Icons.stars, '+${task.rewardExp} 经验',
          theme.colorScheme.primaryContainer,
          onPrimaryContainer: theme.colorScheme.onPrimaryContainer));
    }
    if (task.rewardCurrency > 0) {
      widgets.add(_chip(context, Icons.monetization_on_outlined,
          '+${task.rewardCurrency} 金币', theme.colorScheme.tertiaryContainer,
          onPrimaryContainer: theme.colorScheme.onTertiaryContainer));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: widgets,
    );
  }

  Widget _chip(BuildContext context, IconData icon, String label, Color bg,
      {required Color onPrimaryContainer}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
