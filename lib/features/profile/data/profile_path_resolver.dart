import 'dart:io';

import 'package:path/path.dart' as p;

class ProfilePathResolver {
  const ProfilePathResolver(this._workingDir);

  final Directory _workingDir;

  Directory get directory => Directory(p.join(_workingDir.path, "configs"));

  File file(String fileName) {
    return File(p.join(directory.path, "$fileName.json"));
  }

  File tempFile(String fileName) => file("$fileName.tmp");

  /// 实体层组装出的出站表（`<id>.entities.json`）。
  ///
  /// 启动时**优先用它**：它把节点集合的所有权从"订阅原文"移到"实体表"（`proxy_entities`），
  /// 这样编辑节点才可能生效。订阅基准 `<id>.json` 保持不动，随时可对照、可回退。
  File entityFile(String fileName) => file("$fileName.entities");
}
