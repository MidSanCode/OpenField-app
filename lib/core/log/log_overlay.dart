import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:openfield/core/log/log_entry.dart';
import 'package:openfield/core/log/log_file.dart';
import 'package:openfield/core/log/log_recorder.dart';

/// Global navigator key used to insert the log overlay above every screen.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

OverlayEntry? _logOverlayEntry;

void showLogOverlay() {
  if (_logOverlayEntry != null) return;
  final overlay = appNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  _logOverlayEntry = OverlayEntry(builder: (_) => const _DraggableLogPanel());
  overlay.insert(_logOverlayEntry!);
}

void hideLogOverlay() {
  _logOverlayEntry?.remove();
  _logOverlayEntry = null;
}

void toggleLogOverlay() {
  if (_logOverlayEntry != null) {
    hideLogOverlay();
  } else {
    showLogOverlay();
  }
}

const List<Level> _allLevels = [
  Level.ALL,
  Level.FINEST,
  Level.FINER,
  Level.CONFIG,
  Level.INFO,
  Level.WARNING,
  Level.SEVERE,
  Level.SHOUT,
  Level.OFF,
];

final Map<Level, String> _levelLabels = {
  Level.ALL: 'All',
  Level.FINEST: 'Finest',
  Level.FINER: 'Finer',
  Level.CONFIG: 'Config',
  Level.INFO: 'Info',
  Level.WARNING: 'Warning',
  Level.SEVERE: 'Severe',
  Level.SHOUT: 'Shout',
  Level.OFF: 'Off',
};

Color _levelColor(Level level) {
  switch (level) {
    case Level.FINEST:
    case Level.FINER:
    case Level.CONFIG:
    case Level.INFO:
      return Colors.blue;
    case Level.WARNING:
      return Colors.orange;
    case Level.SEVERE:
    case Level.SHOUT:
      return Colors.red;
    default:
      return Colors.grey;
  }
}

class _DraggableLogPanel extends StatefulWidget {
  const _DraggableLogPanel();

  @override
  State<_DraggableLogPanel> createState() => _DraggableLogPanelState();
}

class _DraggableLogPanelState extends State<_DraggableLogPanel>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(16, 80);
  bool _minimized = false;
  late AnimationController _animController;
  late Animation<double> _heightAnim;
  final ScrollController _scrollController = ScrollController();
  bool _isAtBottom = true;
  int _lastLogCount = 0;
  String _query = '';
  Set<Level> _selectedLevels = {Level.ALL};
  List<LogEntry> _history = [];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
      value: 1.0,
    );
    _heightAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    final atBottom = (max - current).abs() < 1.0 || max <= 0;
    if (atBottom != _isAtBottom) {
      setState(() => _isAtBottom = atBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent > 0) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  void _toggleMinimized() {
    setState(() => _minimized = !_minimized);
    if (_minimized) {
      _animController.reverse();
    } else {
      _animController.forward();
    }
  }

  List<LogEntry> _filtered(List<LogEntry> entries) {
    final q = _query.toLowerCase();
    return entries.where((e) {
      if (_selectedLevels.isNotEmpty &&
          !_selectedLevels.contains(Level.ALL) &&
          !_selectedLevels.contains(e.level)) {
        return false;
      }
      if (q.isNotEmpty) {
        final messageMatch = e.message.toLowerCase().contains(q);
        final errorMatch = e.error?.toString().toLowerCase().contains(q) ?? false;
        if (!messageMatch && !errorMatch) return false;
      }
      return true;
    }).toList();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              _position = Offset(
                _position.dx + details.delta.dx,
                _position.dy + details.delta.dy,
              );
            });
          },
          child: AnimatedBuilder(
            animation: _heightAnim,
            builder: (context, _) {
              const expandedH = 480.0;
              const headerH = 49.0;
              final currentH = headerH + (expandedH - headerH) * _heightAnim.value;
              return Container(
                width: 360,
                height: currentH + 2,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildHeader(context),
                    if (currentH > headerH) ...[
                      Container(height: 1, color: theme.dividerColor),
                      Expanded(child: _buildContent(context)),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text('Log Viewer', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const Spacer(),
          _HeaderButton(
            icon: Icons.history,
            tooltip: 'Load history',
            onTap: () => _showHistorySheet(context),
          ),
          _HeaderButton(
            icon: _minimized ? Icons.open_in_full : Icons.remove,
            tooltip: _minimized ? 'Expand' : 'Minimize',
            onTap: _toggleMinimized,
          ),
          _HeaderButton(
            icon: Icons.delete_sweep,
            tooltip: 'Clear logs',
            onTap: () {
              LogService.instance.clear();
              setState(() => _history = []);
            },
          ),
          _HeaderButton(
            icon: Icons.close,
            tooltip: 'Close',
            onTap: hideLogOverlay,
          ),
        ],
      ),
    );
  }

  Future<void> _showHistorySheet(BuildContext context) async {
    final files = await getLogFiles();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _LogHistorySheet(
        files: files,
        onSelect: (path) async {
          final entries = await readLogFile(path);
          if (!mounted) return;
          setState(() => _history = entries);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: LogService.instance,
      builder: (context, _) {
        final live = LogService.instance.entries;
        final filtered = _filtered([..._history, ...live]);
        if (filtered.length != _lastLogCount) {
          _lastLogCount = filtered.length;
          if (_isAtBottom) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search logs...',
                  hintStyle: const TextStyle(fontSize: 13),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _query.isNotEmpty
                      ? GestureDetector(
                          onTap: () => setState(() => _query = ''),
                          child: const Icon(Icons.close, size: 14),
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _allLevels.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final level = _allLevels[index];
                  final selected = _selectedLevels.contains(level);
                  return FilterChip(
                    label: Text(_levelLabels[level]!),
                    labelStyle: const TextStyle(fontSize: 11),
                    selected: selected,
                    onSelected: (_) => _toggleLevel(level),
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    side: BorderSide(
                      color: selected ? _levelColor(level) : Colors.transparent,
                      width: 1,
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    selectedColor: _levelColor(level).withValues(alpha: 0.25),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} entries',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: theme.dividerColor),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No logs found',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) => _LogEntryTile(entry: filtered[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  void _toggleLevel(Level level) {
    setState(() {
      if (level == Level.ALL) {
        if (_selectedLevels.contains(Level.ALL)) {
          _selectedLevels = {};
        } else {
          _selectedLevels = {Level.ALL};
        }
        return;
      }
      final withoutAll = _selectedLevels.difference({Level.ALL});
      if (withoutAll.contains(level)) {
        _selectedLevels = withoutAll.length == 1 ? <Level>{} : withoutAll.difference({level});
      } else {
        _selectedLevels = {...withoutAll, level};
      }
    });
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatefulWidget {
  final LogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = widget.entry;
    final hasDetails = entry.error != null || entry.stackTrace != null;
    return InkWell(
      onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _levelColor(entry.level).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: _levelColor(entry.level).withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(
                    entry.level.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: _levelColor(entry.level),
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    entry.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                    ),
                  ),
                ),
                if (hasDetails)
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 40, top: 1),
              child: Text(
                _formatTime(entry.timestamp),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(left: 44),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.error != null) ...[
                        Text('Error:', style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600, color: Colors.red, fontSize: 9,
                        )),
                        const SizedBox(height: 1),
                        SelectableText(
                          entry.error.toString(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace', fontSize: 9, color: Colors.red.shade300,
                          ),
                        ),
                      ],
                      if (entry.stackTrace != null) ...[
                        if (entry.error != null) const SizedBox(height: 4),
                        Text('Stack Trace:', style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600, fontSize: 9,
                        )),
                        const SizedBox(height: 1),
                        SelectableText(
                          entry.stackTrace.toString(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace', fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ms = dt.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

class _LogHistorySheet extends StatelessWidget {
  final List<LogFileInfo> files;
  final ValueChanged<String> onSelect;

  const _LogHistorySheet({required this.files, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.history, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Load Log History', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Close'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: files.isEmpty
                  ? Center(
                      child: Text(
                        'No log files found',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        return ListTile(
                          leading: Icon(Icons.description_outlined, color: theme.colorScheme.onSurfaceVariant),
                          title: Text(file.name),
                          subtitle: Text('${file.formattedDate} · ${file.formattedSize}'),
                          trailing: Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                          onTap: () {
                            onSelect(file.path);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
