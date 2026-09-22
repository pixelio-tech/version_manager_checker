import 'package:flutter/material.dart';

import '../models/check_result.dart';

/// Что делать с приложением по результату проверки версии.
enum VmGateVerdict {
  /// Ничего, работаем дальше.
  pass,

  /// Версия заблокирована или обновление обязательно — экран поверх всего.
  block,
}

/// Решение по результату: блокируем, если сервер сказал `blocked`, либо
/// приоритет обновления — `forced`.
///
/// Режим техработ (`status: "maintenance"`) сюда НЕ попадает: закрывать
/// приложение имеет право только блокировка версии или обязательное
/// обновление. Техработы показывают через [VmMaintenanceScreen] или обычным
/// уведомлением, привязанным к ним в админке — см. [vmIsMaintenance].
VmGateVerdict vmVerdictFor(CheckResult? result) {
  if (result == null) return VmGateVerdict.pass;
  if (result.isBlocked || result.status == 'blocked') return VmGateVerdict.block;
  if (result.updatePriority == 'forced' || result.updatePriority == 'required') return VmGateVerdict.block;
  return VmGateVerdict.pass;
}

/// Сервер сообщил о технических работах.
bool vmIsMaintenance(CheckResult? result) => result?.status == 'maintenance';

/// Экран «дальше нельзя»: версия заблокирована или обновление обязательно.
/// Пакет не умеет открывать сторы (это делает приложение), поэтому ссылку
/// отдаёт через [onOpenStore].
class VmBlockedScreen extends StatelessWidget {
  final CheckResult result;

  /// Платформа установки — по ней выбирается ссылка на стор.
  final String platform;

  /// Открыть ссылку на стор (url_launcher и подобное — на стороне приложения).
  final void Function(StoreLink link)? onOpenStore;

  /// Заголовок и подпись можно переопределить: сервер присылает `message`,
  /// но продуктовый текст часто свой.
  final String? title;
  final String? description;

  const VmBlockedScreen({
    super.key,
    required this.result,
    required this.platform,
    this.onOpenStore,
    this.title,
    this.description,
  });

  StoreLink? get _link {
    final links = result.recommendedVersion?.storeLinks ?? const <StoreLink>[];
    if (links.isEmpty) return null;
    for (final l in links) {
      if (l.platform == platform) return l;
    }
    return links.first;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    final head = title ?? (result.isBlocked ? 'Версия больше не поддерживается' : 'Нужно обновиться');
    final text = description?.trim().isNotEmpty == true
        ? description!
        : (result.blockReason?.trim().isNotEmpty == true
              ? result.blockReason!
              : (result.message.trim().isNotEmpty
                    ? result.message
                    : 'Эта версия приложения устарела. Обновите её, чтобы продолжить.'));

    return PopScope(
      // Экран обязателен: системная «назад» его не закрывает.
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.system_update, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(head, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  if (result.recommendedVersion != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Актуальная версия ${result.recommendedVersion!.versionNumber}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (result.recommendedVersion?.changelog.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    Text(result.recommendedVersion!.changelog, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 24),
                  if (link != null)
                    FilledButton(
                      onPressed: onOpenStore == null ? null : () => onOpenStore!(link),
                      child: Text(link.storeName.isEmpty ? 'Обновить' : 'Обновить в ${link.storeName}'),
                    )
                  else
                    Text(
                      'Ссылка на магазин не настроена — добавьте её в админке.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Обёртка приложения: пока проверка разрешает работу — показывает [child],
/// как только сервер сказал «заблокировано» — накрывает экраном обновления.
///
/// ```dart
/// VmUpdateGate(
///   result: result,
///   platform: 'ios',
///   onOpenStore: (l) => launchUrlString(l.url),
///   child: const HomeScreen(),
/// )
/// ```
class VmUpdateGate extends StatelessWidget {
  final CheckResult? result;
  final String platform;
  final void Function(StoreLink link)? onOpenStore;
  final Widget child;
  final String? title;
  final String? description;

  const VmUpdateGate({
    super.key,
    required this.result,
    required this.platform,
    required this.child,
    this.onOpenStore,
    this.title,
    this.description,
  });

  @override
  Widget build(BuildContext context) {
    if (vmVerdictFor(result) == VmGateVerdict.pass) return child;
    return VmBlockedScreen(result: result!, platform: platform, onOpenStore: onOpenStore, title: title, description: description);
  }
}

/// Экран технических работ: приложение живо, но сервер просит подождать.
/// Пакет не показывает его сам — решает приложение, потому что запирать
/// интерфейс имеет право только блокировка версии.
///
/// ```dart
/// if (vmIsMaintenance(result)) {
///   return VmMaintenanceScreen(result: result!, onRetry: () => vm.check(force: true));
/// }
/// ```
class VmMaintenanceScreen extends StatelessWidget {
  final CheckResult result;

  /// Повторная проверка — обычно `VersionManager.instance.check(force: true)`.
  final VoidCallback? onRetry;

  final String? title;
  final String? description;

  const VmMaintenanceScreen({super.key, required this.result, this.onRetry, this.title, this.description});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = description?.trim().isNotEmpty == true
        ? description!
        : (result.message.trim().isNotEmpty
              ? result.message
              : 'Сервис ненадолго недоступен — идут технические работы. Попробуйте позже.');
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.construction_outlined, size: 44, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  title ?? 'Идут технические работы',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: const Text('Проверить ещё раз')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
