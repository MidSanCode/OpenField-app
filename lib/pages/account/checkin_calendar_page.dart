import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// A month-grid sign-in calendar covering the user's registration day through
/// today. Signed days are marked; today can be signed directly; missed past
/// days can be paid to make up.
class CheckinCalendarPage extends StatefulWidget {
  const CheckinCalendarPage({super.key});

  @override
  State<CheckinCalendarPage> createState() => _CheckinCalendarPageState();
}

class _CheckinCalendarPageState extends State<CheckinCalendarPage> {
  final ApiService _apiService = ApiService();

  bool _isLoading = true;
  String? _error;

  String? _registeredAt; // "YYYY-MM-DD"
  String _todayKey = ''; // "YYYY-MM-DD", from the server's timezone
  final Set<String> _signed = {};
  int _streak = 0;
  int _makeupCost = 0;
  int _makeupExp = 0;
  String? _busy; // date currently being processed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _apiService.checkinCalendar(token);
      final signed = data['signed'];
      setState(() {
        _registeredAt = data['registered_at'] as String?;
        _todayKey = data['today'] as String? ?? '';
        _signed
          ..clear()
          ..addAll(signed is List ? signed.whereType<String>() : const []);
        _streak = (data['streak'] as num?)?.toInt() ?? 0;
        _makeupCost = (data['makeup_cost'] as num?)?.toInt() ?? 0;
        _makeupExp = (data['makeup_exp'] as num?)?.toInt() ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Claims today's sign-in directly.
  Future<void> _claimToday() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    if (_busy != null) return;
    setState(() => _busy = _todayKey);
    try {
      final data = await _apiService.claimDailyLogin(token);
      if (!mounted) return;
      _streak = (data['streak'] as num?)?.toInt() ?? _streak;
      setState(() => _signed.add(_todayKey));
      _showSnack('dailyClaimed'.tr());
      await _load();
    } catch (e) {
      if (!mounted) return;
      await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// Confirms and pays to make up a missed past day.
  Future<void> _makeupDate(String date) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    if (_busy != null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('makeupTitle'.tr()),
        content: Text('makeupConfirm'.tr(namedArgs: {
          'date': date,
          'cost': '$_makeupCost',
          'exp': '$_makeupExp',
        })),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = date);
    try {
      await _apiService.makeupByDate(token, date);
      if (!mounted) return;
      setState(() => _signed.add(date));
      _showSnack('makeupDone'.tr(namedArgs: {'date': date}));
      await _load();
    } catch (e) {
      if (!mounted) return;
      await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _dateKey(DateTime d) {
    final local = d.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('checkinCalendarTitle'.tr())),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildCalendar(context),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('loadFailed'.tr()),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: Text('retry'.tr())),
        ],
      ),
    );
  }

  Widget _buildCalendar(BuildContext context) {
    final theme = Theme.of(context);
    final registered = _registeredAt ?? _todayKey;
    final regDate = DateTime.tryParse(registered);
    final to = DateTime.tryParse(_todayKey) ?? DateTime.now();
    final from = (regDate ?? to);

    final months = <(DateTime, DateTime)>[];
    for (var m = DateTime(from.year, from.month, 1);
        !m.isAfter(DateTime(to.year, to.month, 1));
        m = DateTime(m.year, m.month + 1, 1)) {
      final lastDay = DateTime(m.year, m.month + 1, 0);
      final monthEnd = lastDay.isAfter(to) ? to : lastDay;
      final monthStart = m.isBefore(from) ? from : m;
      months.add((monthStart, monthEnd));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummary(theme),
          const SizedBox(height: 16),
          for (final (start, end) in months) ...[
            _buildMonth(theme, start, end),
            const SizedBox(height: 20),
          ],
          _buildLegend(theme),
        ],
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.local_fire_department,
                size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('checkinCalendarTitle'.tr(),
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('taskStreakDays'.tr(namedArgs: {'streak': '$_streak'}),
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (_busy == null && !_signed.contains(_todayKey) && fromIsToday())
              FilledButton.icon(
                onPressed: _claimToday,
                icon: const Icon(Icons.bolt, size: 18),
                label: Text('dailyClaim'.tr()),
              ),
          ],
        ),
      ),
    );
  }

  bool fromIsToday() {
    if (_todayKey.isEmpty) return true;
    final regDate = DateTime.tryParse(_registeredAt ?? '');
    if (regDate == null) return true;
    return _dateKey(regDate) == _todayKey;
  }

  Widget _buildMonth(ThemeData theme, DateTime start, DateTime end) {
    final header = 'checkinMonth'.tr(namedArgs: {
      'year': '${start.year}',
      'month': '${start.month}',
    });
    final firstWeekday = DateTime(start.year, start.month, 1).weekday % 7;
    final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
    final todayKey = _todayKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(header, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    ['一', '二', '三', '四', '五', '六', '日'][i],
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < firstWeekday; i++) const SizedBox.shrink(),
            for (var day = 1; day <= daysInMonth; day++) _buildDay(theme, start, end, day, todayKey),
          ],
        ),
      ],
    );
  }

  Widget _buildDay(ThemeData theme, DateTime monthStart, DateTime monthEnd, int day, String todayKey) {
    final date = DateTime(monthStart.year, monthStart.month, day);
    final key = _dateKey(date);
    final inRange = !date.isBefore(monthStart) && !date.isAfter(monthEnd);
    final isToday = key == todayKey;
    final isSigned = _signed.contains(key);
    final busy = _busy == key;

    if (!inRange) return const SizedBox.shrink();

    final regDate = DateTime.tryParse(_registeredAt ?? '');
    final canMakeup = !isSigned && !isToday && regDate != null &&
        !date.isBefore(regDate);

    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: (canMakeup || (isToday && !isSigned)) && busy == false
            ? () => isToday ? _claimToday() : _makeupDate(key)
            : null,
        child: Container(
          decoration: BoxDecoration(
            color: isToday
                ? theme.colorScheme.primaryContainer
                : isSigned
                    ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Text('$day',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isToday ? FontWeight.w700 : null,
                            color: isToday
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurface,
                          )),
                      if (isSigned)
                        Positioned(
                          bottom: 2,
                          child: Icon(Icons.check_circle,
                              size: 12,
                              color: theme.colorScheme.primary),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _LegendItem(color: theme.colorScheme.primaryContainer, label: 'legendToday'.tr()),
          _LegendItem(color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.5), label: 'legendSigned'.tr()),
          _LegendItem(color: Colors.transparent, label: 'legendMissed'.tr()),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}