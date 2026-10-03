import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:hiddify/core/router/deep_linking/url_protocol/protocol.dart';
import 'package:win32/win32.dart';

const _hive = HKEY_CURRENT_USER;

class WindowsProtocolHandler extends ProtocolHandler {
  @override
  bool get supportsAssociation => defaultTargetPlatform == TargetPlatform.windows;

  @override
  String get executable => Platform.resolvedExecutable;

  /// 读 `HKCU\SOFTWARE\Classes\<scheme>\shell\open\command` 的默认值。
  ///
  /// 只读、且把一切失败都折叠成 null（"没注册"）：读不到注册表时应当
  /// **保守地什么都不做**，绝不能因此误判成"是别人的"而放弃自己的名字，
  /// 也不能误判成"是空的"而重复写。
  @override
  String? registeredCommand(String scheme) {
    if (!supportsAssociation) return null;

    final subKey = TEXT('${_regPrefix(scheme)}\\shell\\open\\command');
    final valueName = TEXT('');
    final pdwType = calloc<Uint32>();
    final pcbData = calloc<Uint32>();
    try {
      // 先问大小（传 null 数据指针，RegGetValue 会回报所需字节数）。
      var status = RegGetValue(
        _hive,
        subKey,
        valueName,
        RRF_RT_REG_SZ,
        pdwType,
        nullptr,
        pcbData,
      );
      if (status != ERROR_SUCCESS) return null;

      final size = pcbData.value;
      if (size < 2) return null;

      final buffer = wsalloc(size ~/ 2 + 1);
      try {
        pcbData.value = size;
        status = RegGetValue(
          _hive,
          subKey,
          valueName,
          RRF_RT_REG_SZ,
          pdwType,
          buffer,
          pcbData,
        );
        if (status != ERROR_SUCCESS) return null;

        final value = buffer.toDartString();
        return value.isEmpty ? null : value;
      } finally {
        free(buffer);
      }
    } catch (_) {
      // 注册表不可读（权限/畸形值）⇒ 当作没注册
      return null;
    } finally {
      free(subKey);
      free(valueName);
      free(pdwType);
      free(pcbData);
    }
  }

  @override
  void register(String scheme, {String? executable, List<String>? arguments}) {
    if (!supportsAssociation) return;

    final prefix = _regPrefix(scheme);
    final capitalized = scheme[0].toUpperCase() + scheme.substring(1);
    final args = getArguments(arguments).map((a) => _sanitize(a));
    final cmd = '${executable ?? Platform.resolvedExecutable} ${args.join(' ')}';

    _regCreateStringKey(_hive, prefix, '', 'URL:$capitalized');
    _regCreateStringKey(_hive, prefix, 'URL Protocol', '');
    _regCreateStringKey(_hive, '$prefix\\shell\\open\\command', '', cmd);
  }

  @override
  void unregister(String scheme) {
    if (!supportsAssociation) return;

    final txtKey = TEXT(_regPrefix(scheme));
    try {
      RegDeleteTree(HKEY_CURRENT_USER, txtKey);
    } finally {
      free(txtKey);
    }
  }

  String _regPrefix(String scheme) => 'SOFTWARE\\Classes\\$scheme';

  int _regCreateStringKey(int hKey, String key, String valueName, String data) {
    final txtKey = TEXT(key);
    final txtValue = TEXT(valueName);
    final txtData = TEXT(data);
    try {
      return RegSetKeyValue(hKey, txtKey, txtValue, REG_SZ, txtData, txtData.length * 2 + 2);
    } finally {
      free(txtKey);
      free(txtValue);
      free(txtData);
    }
  }

  String _sanitize(String rawValue) {
    final value = rawValue.replaceAll('%s', '%1').replaceAll('"', '\\"');
    return '"$value"';
  }
}
