import 'package:flutter/material.dart';

/// 桌面端窗口尺寸约束。
///
/// 被 core/preferences（windowSize 持久化默认值）与
/// features/window（WindowOptions）共同使用，故下沉到 core/model。
const minimumWindowSize = Size(368, 568);
const defaultWindowSize = Size(868, 668);
