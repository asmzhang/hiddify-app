import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/http_client/http_client_provider.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_repository.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'proxy_data_providers.g.dart';

@Riverpod(keepAlive: true)
ProxyRepository proxyRepository(Ref ref) {
  return ProxyRepositoryImpl(singbox: ref.watch(hiddifyCoreServiceProvider), client: ref.watch(httpClientProvider));
}

/// 实体落库（订阅配置 → 分组 + 节点实体）。见 `docs/design/nekobox-parity.md` §8.6 第 3 步。
///
/// 依赖方向单向：只用 db / 路径解析 / 内核，**不依赖** profile 仓储，
/// 所以 `profileRepository` 反过来注入它不会成环。
@Riverpod(keepAlive: true)
ProxyEntityRepository proxyEntityRepository(Ref ref) {
  return ProxyEntityRepository(
    db: ref.watch(dbProvider),
    pathResolver: ref.watch(profilePathResolverProvider),
    singbox: ref.watch(hiddifyCoreServiceProvider),
  );
}
