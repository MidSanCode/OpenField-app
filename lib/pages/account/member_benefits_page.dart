import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/widgets/verified_badge.dart';

/// The maximum number of gradient color stops the client editor may hold,
/// kept in sync with the server's MemberMaxNameColors.
const int memberMaxNameColors = 6;

/// The supported gradient orientations, kept in sync with the server's
/// NameGradientDirections list.
const List<String> memberGradientDirections = [
  'left_right',
  'right_left',
  'top_bottom',
  'bottom_top',
  'top_left_bottom_right',
  'bottom_left_top_right',
];

/// 会员权益 (member benefits) sub-page: shows the current membership perks and
/// hosts the display-name style editor. The editor is gated by tier: Lv.1
/// presets only, Lv.2+ any hex, Lv.3+ multi-color gradients (≤6 stops with a
/// selectable overall direction), Lv.4 animated gradient.
class MemberBenefitsPage extends StatefulWidget {
  const MemberBenefitsPage({super.key});

  @override
  State<MemberBenefitsPage> createState() => _MemberBenefitsPageState();
}

class _MemberBenefitsPageState extends State<MemberBenefitsPage> {
  final ApiService _apiService = ApiService();

  late List<String> _colors;
  late String _direction;
  late bool _dynamic;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromUser();
  }

  void _loadFromUser() {
    final user = Provider.of<AuthService>(context, listen: false).user;
    final nameColors = user?.nameColors ?? const <String>[];
    if (nameColors.isNotEmpty) {
      _colors = List.of(nameColors);
    } else {
      _colors = [
        if ((user?.nameColor ?? '').isNotEmpty) user!.nameColor,
        if ((user?.nameColorTo ?? '').isNotEmpty) user!.nameColorTo,
      ];
    }
    _direction = (user?.nameGradientDirection ?? '').isNotEmpty
        ? user!.nameGradientDirection
        : 'left_right';
    _dynamic = user?.nameDynamic ?? false;
  }

  User? get _user => Provider.of<AuthService>(context).user;

  /// Read-only snapshot for event handlers, which must not subscribe.
  User? get _userSnapshot => Provider.of<AuthService>(context, listen: false).user;

  bool get _isMember => _userSnapshot?.hasActiveMembership ?? false;

  int get _maxColors {
    final level = _userSnapshot?.memberLevel ?? 0;
    if (_isMember && level >= 3) return memberMaxNameColors;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    final isMember = _isMember;
    final tierLevel = user?.memberLevel ?? 0;
    final allowGradient = tierLevel >= 3 && isMember;
    final allowDynamic = tierLevel >= 4 && isMember;

    return Scaffold(
      appBar: AppBar(title: Text('memberBenefitsTitle'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isMember)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'nameStyleNeedMember'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Live preview with the same rendering used across the app.
          Card(
            margin: EdgeInsets.zero,
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: VerifiedName(
                  name: user?.displayName ?? '',
                  verified: user?.isVerified ?? false,
                  memberLevel: tierLevel,
                  memberActive: isMember,
                  nameColor: _colors.isNotEmpty ? _colors.first : '',
                  nameColorTo: _colors.length > 1 ? _colors[1] : '',
                  nameColors: _colors,
                  nameGradientDirection: _direction,
                  nameDynamic: _dynamic,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (isMember && tierLevel == 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'nameStylePresetsHint'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Text('nameStyleColors'.tr(), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'nameStyleMaxColors'.tr(namedArgs: {'max': '$_maxColors'}),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _buildColorList(theme, isMember: isMember, allowGradient: allowGradient),
          const SizedBox(height: 20),
          Text('nameStyleDirection'.tr(), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildDirectionPicker(theme, enabled: allowGradient),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('nameStyleDynamic'.tr()),
            subtitle: allowDynamic
                ? null
                : Text(
                    'nameStyleDynamicHint'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
            value: _dynamic && allowDynamic,
            onChanged: allowDynamic ? (v) => setState(() => _dynamic = v) : null,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isMember && !_saving ? _save : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text('save'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildColorList(ThemeData theme,
      {required bool isMember, required bool allowGradient}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _colors.length; i++)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: isMember && allowGradient
                        ? () => _editColor(i)
                        : null,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: nameColorFromHex(_colors[i]) ?? Colors.grey,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _colors[i],
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isMember && _colors.length > 1)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() => _colors.removeAt(i)),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            if (isMember && _colors.length < _maxColors)
              InkWell(
                onTap: () => _addColor(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: const Icon(Icons.add, size: 22),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDirectionPicker(ThemeData theme, {required bool enabled}) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final dir in memberGradientDirections)
          _directionChip(theme, dir, enabled: enabled),
      ],
    );
  }

  Widget _directionChip(ThemeData theme, String dir, {required bool enabled}) {
    final selected = _direction == dir;
    final colors = _colors.isNotEmpty
        ? _colors.map(nameColorFromHex).whereType<Color>().toList()
        : [theme.colorScheme.primary, theme.colorScheme.tertiary];
    final beginEnd = gradientDirectionOf(dir);
    return InkWell(
      onTap: enabled ? () => setState(() => _direction = dir) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: colors.length >= 2 ? colors : [colors.first, colors.first],
                  begin: beginEnd.$1,
                  end: beginEnd.$2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _directionLabel(dir),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _directionLabel(String dir) {
    switch (dir) {
      case 'right_left':
        return 'nameStyleDirectionRightLeft'.tr();
      case 'top_bottom':
        return 'nameStyleDirectionTopBottom'.tr();
      case 'bottom_top':
        return 'nameStyleDirectionBottomTop'.tr();
      case 'top_left_bottom_right':
        return 'nameStyleDirectionTopLeftBottomRight'.tr();
      case 'bottom_left_top_right':
        return 'nameStyleDirectionBottomLeftTopRight'.tr();
      case 'left_right':
      default:
        return 'nameStyleDirectionLeftRight'.tr();
    }
  }

  Future<void> _addColor() async {
    final picked = await _pickColor(context, initial: '');
    if (picked == null || !mounted) return;
    if (_colors.length >= _maxColors) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('nameStyleMaxColors'.tr(namedArgs: {'max': '$_maxColors'})),
          ),
        );
      }
      return;
    }
    setState(() => _colors = [..._colors, picked]);
  }

  Future<void> _editColor(int index) async {
    final picked = await _pickColor(context, initial: _colors[index]);
    if (picked == null || !mounted) return;
    setState(() {
      _colors = List.of(_colors);
      _colors[index] = picked;
    });
  }

  /// A dialog for picking a color: preset swatches plus an optional hex input.
  /// Returns the selected "#RRGGBB" string, or null when cancelled.
  Future<String?> _pickColor(BuildContext context, {required String initial}) async {
    final isMember = _isMember;
    final level = _userSnapshot?.memberLevel ?? 0;
    final presetsOnly = isMember && level == 1;
    final controller = TextEditingController(
      text: (initial.isNotEmpty && initial.startsWith('#')) ? initial.substring(1) : initial,
    );
    String? selected = initial;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          Color? preview = nameColorFromHex(selected ?? '');
          return AlertDialog(
            title: Text('nameStylePickColor'.tr()),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final hex in _allPresets())
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              selected = hex;
                              controller.text = hex.substring(1);
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: nameColorFromHex(hex) ?? Colors.grey,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected == hex
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outlineVariant,
                                width: selected == hex ? 3 : 1,
                              ),
                            ),
                            child: selected == hex
                                ? const Icon(Icons.check, color: Colors.white, size: 18)
                                : null,
                          ),
                        ),
                    ],
                  ),
                  if (!presetsOnly) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.text,
                      decoration: InputDecoration(
                        labelText: 'nameStyleColor'.tr(),
                        hintText: 'RRGGBB',
                        border: const OutlineInputBorder(),
                        prefixIcon: preview != null
                            ? Container(
                                width: 8,
                                margin: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: preview,
                                  shape: BoxShape.circle,
                                ),
                              )
                            : null,
                      ),
                      onChanged: (v) {
                        setState(() {
                          selected = '#${v.trim()}';
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('cancel'.tr()),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = _normalizeHex(selected ?? '');
                  if (normalized.isEmpty) return;
                  Navigator.of(dialogContext).pop(normalized);
                },
                child: Text('confirm'.tr()),
              ),
            ],
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  List<String> _allPresets() => const [
        '#FF5252', '#FF7043', '#FFA726', '#FFCA28',
        '#9CCC65', '#66BB6A', '#26A69A', '#29B6F6',
        '#42A5F5', '#5C6BC0', '#AB47BC', '#EC407A',
      ];

  /// Normalizes a hex string to "#RRGGBB", or returns empty when invalid.
  String _normalizeHex(String v) {
    var s = v.trim();
    if (!s.startsWith('#')) s = '#$s';
    final hex = s.substring(1);
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex) ? s.toUpperCase() : '';
  }

  Future<void> _save() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      final normalized = _colors.map(_normalizeHex).where((c) => c.isNotEmpty).toList();
      await _apiService.updateNameStyle(
        token,
        color: normalized.isNotEmpty ? normalized.first : '',
        colorTo: normalized.length > 1 ? normalized[1] : '',
        colors: normalized,
        direction: _direction,
        animated: _dynamic,
        avatarFrame: authService.user?.avatarFrame ?? '',
      );
      await authService.fetchCurrentUser();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('nameStyleSaved'.tr())),
      );
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
