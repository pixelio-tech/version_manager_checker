import 'notification_style.dart';

/// Response of `POST /api/mobile/v2/check-version` (see
/// `version_manager_v3_back/internal/check/compute.go` `Result`).
class CheckResult {
  final String status; // active | update_available | blocked | maintenance
  final bool isBlocked;
  final String? blockReason;
  final String updatePriority;

  /// Куда обновляться: приходит только вместе с блокировкой, для экрана
  /// обязательного обновления ([VmBlockedScreen]). Мягкое «доступно
  /// обновление» сервер присылает уведомлением, а не этим полем.
  final UpdateTarget? updateTarget;
  final List<NotificationPayload> notifications;
  final int nextCheckInterval;
  final String configHash;
  final String message;
  final String serverTimestamp;

  const CheckResult({
    required this.status,
    required this.isBlocked,
    this.blockReason,
    required this.updatePriority,
    this.updateTarget,
    required this.notifications,
    required this.nextCheckInterval,
    required this.configHash,
    required this.message,
    required this.serverTimestamp,
  });

  factory CheckResult.fromJson(Map<String, dynamic> json) => CheckResult(
    status: json['status'] as String,
    isBlocked: json['isBlocked'] as bool? ?? false,
    blockReason: json['blockReason'] as String?,
    updatePriority: json['updatePriority'] as String? ?? 'none',
    // Имя поля в ответе старше модели: по нему ходят и старые сборки SDK.
    updateTarget: json['recommendedVersion'] != null
        ? UpdateTarget.fromJson(json['recommendedVersion'] as Map<String, dynamic>)
        : null,
    notifications: (json['notifications'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(NotificationPayload.fromJson)
        .toList(),
    nextCheckInterval: (json['nextCheckInterval'] as num?)?.toInt() ?? 3600,
    configHash: json['configHash'] as String? ?? '',
    message: json['message'] as String? ?? '',
    serverTimestamp: json['serverTimestamp'] as String? ?? '',
  );
}

/// Цель обязательного обновления: актуальная сборка платформы, ссылки на
/// стор и заметка к релизу.
class UpdateTarget {
  final String versionNumber;
  final int buildNumber;
  final List<StoreLink> storeLinks;
  final String changelog;

  const UpdateTarget({
    required this.versionNumber,
    required this.buildNumber,
    required this.storeLinks,
    required this.changelog,
  });

  factory UpdateTarget.fromJson(Map<String, dynamic> json) => UpdateTarget(
    versionNumber: json['versionNumber'] as String,
    buildNumber: (json['buildNumber'] as num).toInt(),
    storeLinks: (json['storeLinks'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>().map(StoreLink.fromJson).toList(),
    changelog: json['changelog'] as String? ?? '',
  );
}

class StoreLink {
  final String platform;
  final String storeName;
  final String url;

  const StoreLink({required this.platform, required this.storeName, required this.url});

  factory StoreLink.fromJson(Map<String, dynamic> json) =>
      StoreLink(platform: json['platform'] as String, storeName: json['storeName'] as String, url: json['url'] as String);
}

/// One delivered, localized notification — content + presentation style +
/// default tap action. `type` drives which widget renders it.
class NotificationPayload {
  final String id;
  final String type; // banner | modal | bottomSheet | localPush
  final String title;
  final String body;
  final Map<String, dynamic> action;
  final NotificationStyle style;

  const NotificationPayload({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.action,
    required this.style,
  });

  factory NotificationPayload.fromJson(Map<String, dynamic> json) => NotificationPayload(
    id: json['id'] as String,
    type: json['type'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    action: json['action'] is Map<String, dynamic> ? json['action'] as Map<String, dynamic> : const {},
    // `ui` — дерево оформления (корень card). Старое плоское `style` приходит
    // только с замороженной ручки v1, куда этот пакет больше не ходит.
    style: json['ui'] is Map<String, dynamic>
        ? NotificationStyle.fromJson(json['ui'] as Map<String, dynamic>)
        : const NotificationStyle(),
  );
}
