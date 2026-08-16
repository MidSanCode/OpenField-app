import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/widgets/verified_badge.dart';

/// Editor for the user's display-name styling. Available options are gated by
/// the active membership tier (Lv.1 presets only, Lv.2+ any hex, Lv.3+
/// gradients, Lv.4 animated gradient); previews render live using the same
/// [VerifiedName] widget used across the app.
class NameStylePage extends StatefulWidget {
  const NameStylePage({super.key});

  @override
  State<NameStylePage> createState() => _NameStylePageState();
}

class _NameStylePageState extends State<NameStylePage> {
  final ApiService _apiService = ApiService();

  late String _color;
  late String _colorTo;
  late bool _dynamic;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = Provider.of<AuthService>(context, listen: false).user;
    _color = user?.nameColor ?? '';
    _colorTo = user?.nameColorTo ?? '';
    _dynamic = user?.nameDynamic ?? false;
  }

  User? get _user => Provider.of<AuthService>(context).user;

  bool get _isMember => _user?.hasActiveMembership ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _user;
    final isMember = _isMember;
    final tierLevel = _user?.memberLevel ?? 0;
    final allowGradient = tierLevel >= 3 && isMember;
    final allowDynamic = tierLevel >= 4 && isMember;

    return Scaffold(
      appBar: AppBar(title: Text('nameStyleTitle'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
                  nameColor: _color,
                  nameColorTo: _colorTo,
                  nameDynamic: _dynamic,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          Text('nameStyleColor'.tr(),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildColorPicker(theme, selected: _color),
          const SizedBox(height: 20),
          Text('nameStyleGradientTo'.tr(),
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  enabled: allowGradient,
                  controller: TextEditingController(text: _colorTo),
                  onChanged: allowGradient ? (v) => setState(() => _colorTo = _validHex(v)) : null,
                  decoration: InputDecoration(
                    hintText: '#RRGGBB',
                    border: const OutlineInputBorder(),
                    prefixIcon: Container(
                      width: 8,
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: nameColorFromHex(_colorTo),
                        shape: BoxShape.circle,
                      ),
                    ),
                    suffixIcon: _colorTo.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: allowGradient
                                ? () => setState(() => _colorTo = '')
                                : null,
                          )
                        : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('nameStyleDynamic'.tr()),
            value: _dynamic && allowDynamic,
            onChanged: allowDynamic
                ? (v) => setState(() => _dynamic = v)
                : null,
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

  Widget _buildColorPicker(ThemeData theme, {required String selected}) {
    final isMember = _isMember;

    Widget swatch(String hex, {bool enabled = true}) {
      final color = nameColorFromHex(hex) ?? Colors.grey;
      final isSelected = _color.toLowerCase() == hex.toLowerCase();
      return InkWell(
        onTap: enabled
            ? () {
                setState(() {
                  _color = hex;
                  if (_colorTo== hex) _colorTo = '';
                });
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: isSelected ? 3 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 20)
              : null,
        ),
      );
    }

    // Presets are always offered as quick picks; Lv.1 may only pick from these
    // (the server enforces the tier caps). Higher tiers may also type any hex.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final hex in _allPresets())
              swatch(hex, enabled: isMember),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          enabled: isMember,
          controller: TextEditingController(text: _color),
          onChanged: isMember
              ? (v) => setState(() {
                    final hex = _validHex(v);
                    if (hex.isNotEmpty) _color = hex;
                  })
              : null,
          decoration: const InputDecoration(
            hintText: '#RRGGBB',
            border: OutlineInputBorder(),
            prefixText: '  ',
          ),
          onSubmitted: (v) {
            final hex = _validHex(v);
            if (hex.isNotEmpty) setState(() => _color = hex);
          },
        ),
      ],
    );
  }

  List<String> _allPresets() => const [
        '#FF5252', '#FF7043', '#FFA726', '#FFCA28',
        '#9CCC65', '#66BB6A', '#26A69A', '#29B6F6',
        '#42A5F5', '#5C6BC0', '#AB47BC', '#EC407A',
      ];

  String _validHex(String v) {
    var s = v.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('#')) s = '#$s';
    if (s.length != 7) return s;
    final hex = s.substring(1);
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex) ? s : '';
  }

  Future<void> _save() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      await _apiService.updateNameStyle(
        token,
        color: _color,
        colorTo: _colorTo,
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