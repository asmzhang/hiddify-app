import 'dart:convert';

/// sing-box JSON 深合并器 —— NekoBox `Util.mergeJSON`/`mergeMap` 的 Dart 等价实现。
///
/// 规格：`S:\test\NekoBoxForAndroid\app\src\main\java\moe\matsuri\nb4a\utils\Util.kt:129-159`
/// 语义表：
/// | 输入键              | 行为                                   |
/// |--------------------|----------------------------------------|
/// | 标量 / 类型不同     | 直接覆盖 `dst[k] = v`                   |
/// | 双方都是 Map        | 递归深合并                              |
/// | `key+`（值为 List） | 追加到 dst 现有 List 末尾（无则新建）     |
/// | `+key`（值为 List） | 前插到 dst 现有 List 头部（无则新建）     |
/// | 裸键（值为 List）   | 整体替换                                |
///
/// 设计文档：docs/design/custom-config-2026-09-18.md §1
///
/// 注意：dst 会被**就地修改**并返回（与 NekoBox 一致）；调用方若需保留原件应自行
/// 先 `jsonDecode(jsonEncode(src))` 拷贝。
Map<String, dynamic> deepMergeJson(Map<String, dynamic> dst, Map<String, dynamic> src) {
  src.forEach((key, value) {
    if (value is Map<String, dynamic> && dst[key] is Map<String, dynamic>) {
      dst[key] = deepMergeJson(dst[key] as Map<String, dynamic>, value);
    } else if (value is List && key.startsWith('+') == true) {
      // "+key"：前插。NekoBox 在 List 分支里只 removePrefix，不检查结尾 +
      final dstKey = key.substring(1);
      final current = (dst[dstKey] as List?)?.toList() ?? [];
      dst[dstKey] = [...value, ...current];
    } else if (value is List && key.endsWith('+') == true) {
      // "key+"：追加
      final dstKey = key.substring(0, key.length - 1);
      final current = (dst[dstKey] as List?)?.toList() ?? [];
      dst[dstKey] = [...current, ...value];
    } else {
      dst[key] = value;
    }
  });
  return dst;
}

/// 解析用户输入的自定义配置 JSON，失败抛 [FormatException]（调用方负责 UI 拦截）。
Map<String, dynamic> parseCustomConfig(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return {};
  final decoded = jsonDecode(trimmed);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('custom config must be a JSON object');
  }
  return decoded;
}
