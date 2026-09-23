import 'dart:io';

import 'package:path/path.dart' as p;

class LogPathResolver {
  const LogPathResolver(this._workingDir);

  final Directory _workingDir;

  Directory get directory => _workingDir;

  File coreFile() {
    // 2026-09-23 根因修复：内核（hiddify-core）的日志落盘位置 = 工作目录下的
    // **data 子目录**（`data\box.log`，实测 412KB 真实日志），而本 resolver 曾指向
    // 工作目录根（`box.log` = 0 字节空文件）→ 日志页永远转圈无内容。
    // 对齐内核实际落盘路径（NekoBox 语义：日志页显示内核日志）。
    return File(p.join(directory.path, "data", "box.log"));
  }

  File appFile() {
    return File(p.join(directory.path, "app.log"));
  }
}
