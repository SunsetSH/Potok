import 'package:flutter/material.dart';

import 'theme.dart';

class SettingsDestination {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;

  const SettingsDestination({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });
}

Future<void> showSettingsScreen(
  BuildContext context, {
  required List<SettingsDestination> destinations,
}) {
  final compact = MediaQuery.sizeOf(context).width < 720;
  if (compact) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => _MobileSettingsHome(destinations: destinations),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (_) => _DesktopSettingsDialog(destinations: destinations),
  );
}

class _DesktopSettingsDialog extends StatefulWidget {
  final List<SettingsDestination> destinations;

  const _DesktopSettingsDialog({required this.destinations});

  @override
  State<_DesktopSettingsDialog> createState() => _DesktopSettingsDialogState();
}

class _DesktopSettingsDialogState extends State<_DesktopSettingsDialog> {
  late SettingsDestination _selected = widget.destinations.first;

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 48).clamp(680.0, 980.0);
    final height = (size.height - 48).clamp(480.0, 760.0);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        key: const ValueKey('settings-desktop'),
        width: width,
        height: height,
        child: Row(
          children: [
            SizedBox(
              width: 254,
              child: Material(
                color: c.surface2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                      child: Text(
                        'Настройки',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: widget.destinations.length,
                        itemBuilder: (context, index) {
                          final item = widget.destinations[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: ListTile(
                              key: ValueKey('settings-nav-${item.id}'),
                              selected: item.id == _selected.id,
                              selectedTileColor: c.accentSoft,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  c.radiusSmall,
                                ),
                              ),
                              leading: Icon(item.icon, size: 20),
                              title: Text(
                                item.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10),
                              ),
                              onTap: () => setState(() => _selected = item),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            VerticalDivider(width: 1, color: c.line),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 18, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selected.title,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: c.text,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _selected.subtitle,
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.line),
                  Expanded(
                    child: SingleChildScrollView(
                      key: PageStorageKey('settings-page-${_selected.id}'),
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: KeyedSubtree(
                            key: ValueKey('settings-content-${_selected.id}'),
                            child: _selected.builder(context),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSettingsHome extends StatelessWidget {
  final List<SettingsDestination> destinations;

  const _MobileSettingsHome({required this.destinations});

  @override
  Widget build(BuildContext context) {
    final c = PotokColors.of(context);
    return Scaffold(
      key: const ValueKey('settings-mobile'),
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: destinations.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: c.line),
        itemBuilder: (context, index) {
          final item = destinations[index];
          return ListTile(
            key: ValueKey('settings-nav-${item.id}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            leading: Icon(item.icon, color: c.accent),
            title: Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(item.subtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => _MobileSettingsPage(destination: item),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileSettingsPage extends StatelessWidget {
  final SettingsDestination destination;

  const _MobileSettingsPage({required this.destination});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(destination.title)),
      body: SingleChildScrollView(
        key: ValueKey('settings-content-${destination.id}'),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: destination.builder(context),
      ),
    );
  }
}
