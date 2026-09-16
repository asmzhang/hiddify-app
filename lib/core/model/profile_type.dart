/// Profile 来源类型：远端订阅或本地文件。
///
/// 属于持久层共享模型：core/db 的 `ProfileEntries.type` 列
/// (`textEnum<ProfileType>`) 与 features/profile 的领域模型都要用它，
/// 故下沉到 core/model，避免 db.dart 逆向依赖 features。
enum ProfileType { remote, local }
