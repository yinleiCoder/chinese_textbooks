import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/providers.dart';
import '../../utils/utils.dart';
import '../../values/values.dart';
import '../catalog/catalog_setup_page.dart';
import '../shell/home_shell.dart';

/// 设置页。
///
/// 三个分组：教材目录（数据管理）、外观与语言（偏好）、关于（免责声明）。
/// 偏好项直接复用既有的 `AppThemeProvider` / `AppLocaleProvider`，
/// 它们已经在启动阶段读出了用户上次的选择。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ShellPageScaffold(
      title: AppStrings.tabSettings,
      child: ListView(
        children: <Widget>[
          const _CatalogSection(),
          const _Divider(),
          const _AppearanceSection(),
          const _Divider(),
          const _AboutSection(),
          SizedBox(height: AppDimens.gapXl),
        ],
      ),
    );
  }
}

/// 教材目录的数据管理。
class _CatalogSection extends StatelessWidget {
  const _CatalogSection();

  @override
  Widget build(BuildContext context) {
    final CatalogProvider catalog = context.watch<CatalogProvider>();

    return _Section(
      title: AppStrings.settingsCatalog,
      children: <Widget>[
        _KeyValueTile(
          label: AppStrings.settingsCatalogCount,
          value: catalog.hasData
              ? AppStrings.catalogBookCount(catalog.bookCount)
              : AppStrings.settingsCatalogNotReady,
        ),
        FutureBuilder<int>(
          // provider 变化时重新取一次；目录更新后大小会变。
          key: ValueKey<int>(catalog.bookCount),
          future: catalog.diskUsageBytes(),
          builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
            return _KeyValueTile(
              label: AppStrings.settingsCatalogSize,
              value: snapshot.hasData ? formatBytes(snapshot.data!) : '—',
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.refresh_rounded),
          title: const Text(AppStrings.settingsCatalogRedownload),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext _) =>
                  const CatalogSetupPage(showAppBar: true),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text(AppStrings.settingsCatalogClear),
          onTap: () => _confirmClear(context, catalog),
        ),
      ],
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    CatalogProvider catalog,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text(AppStrings.settingsCatalogClearConfirmTitle),
        content: const Text(AppStrings.settingsCatalogClearConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await catalog.clearLocal();
    if (context.mounted) {
      context.showSnackBar(AppStrings.settingsCatalogCleared);
    }
  }
}

/// 外观设置。
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    final AppThemeProvider theme = context.watch<AppThemeProvider>();

    return _Section(
      title: AppStrings.themeTitle,
      children: <Widget>[
        RadioGroup<ThemeMode>(
          groupValue: theme.themeMode,
          onChanged: (ThemeMode? mode) {
            if (mode != null) {
              theme.setThemeMode(mode);
            }
          },
          child: Column(
            children: <Widget>[
              for (final (ThemeMode mode, String label) entry
                  in <(ThemeMode, String)>[
                    (ThemeMode.system, AppStrings.themeSystem),
                    (ThemeMode.light, AppStrings.themeLight),
                    (ThemeMode.dark, AppStrings.themeDark),
                  ])
                RadioListTile<ThemeMode>(
                  value: entry.$1,
                  title: Text(entry.$2),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 关于与免责声明。
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return _Section(
      title: AppStrings.settingsAbout,
      children: <Widget>[
        const _KeyValueTile(
          label: AppStrings.settingsVersion,
          value: AppConfig.appVersion,
        ),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppDimens.gapMd,
            vertical: AppDimens.gapSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                AppStrings.settingsDisclaimer,
                style: TextStyle(
                  fontSize: AppDimens.fontBodySmall,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              SizedBox(height: AppDimens.gapXs),
              Text(
                AppStrings.settingsDisclaimerBody,
                style: TextStyle(
                  fontSize: AppDimens.fontCaption,
                  color: scheme.onSurfaceVariant,
                  height: AppDimens.lineHeightLoose,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 设置分组。
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.only(
            left: AppDimens.gapMd,
            top: AppDimens.gapLg,
            bottom: AppDimens.gapXs,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: AppDimens.fontBodySmall,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

/// 只读的键值行。
class _KeyValueTile extends StatelessWidget {
  const _KeyValueTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: AppDimens.fontBodySmall,
          color: context.secondaryTextColor,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1);
}
