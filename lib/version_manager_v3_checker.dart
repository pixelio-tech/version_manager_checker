/// Проверка версии и внутриигровые уведомления для Version Manager v3.
///
/// Три слоя, каждый можно брать отдельно:
/// - [VersionManager] — фасад: помнит ключ, `instanceId` и ETag, ходит на
///   сервер сам, умеет периодическую проверку и показ всех уведомлений.
///   Ничего не бросает: исход проверки — [VmCheckOutcome].
/// - [VmV3Client] — голый HTTP к `check-version` / `notification-event`.
/// - [presentVmNotification], [VmUpdateGate] — отрисовка уведомления и
///   экран обязательного обновления.
library;

export 'src/client.dart';
export 'src/events.dart' show VmEventQueue;
export 'src/models/check_result.dart';
export 'src/outcome.dart';
export 'src/push_channel.dart';
export 'src/models/notification_blocks.dart';
export 'src/models/notification_style.dart';
export 'src/storage.dart';
export 'src/ui/block_renderer.dart' show NotificationBlocks;
export 'src/ui/notification_presenter.dart';
export 'src/ui/update_gate.dart';
export 'src/log.dart' show VmLogEvent, VmLogLevel, VmLogSink;
export 'src/version_manager.dart';
