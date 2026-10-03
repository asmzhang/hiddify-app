import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/per_app_proxy/model/pkg_flag.dart';

void main() {
  group('invertSelectionFlag', () {
    // 对齐 NekoBox `action_invert_selections`（AppListActivity.kt:241-259）：
    // 逐包翻转「可见勾选态」。可见勾选态 == PkgFlag.checkboxValue(flag)
    // （forceDeselection 优先，故 `userSelection | forceDeselection` 视为未勾选）。
    final cases = <int, int>{
      0: PkgFlag.userSelection.value, // 无声明行的包 → 反选后选中
      PkgFlag.userSelection.value: PkgFlag.forceDeselection.value,
      PkgFlag.forceDeselection.value: PkgFlag.userSelection.value,
      // 3 的可见勾选态是「未勾选」（forceDeselection 优先）→ 反选后应变成「已勾选」
      PkgFlag.userSelection.value | PkgFlag.forceDeselection.value: PkgFlag.userSelection.value,
      PkgFlag.autoSelection.value: PkgFlag.autoSelection.value | PkgFlag.userSelection.value,
      PkgFlag.autoSelection.value | PkgFlag.userSelection.value:
          PkgFlag.autoSelection.value | PkgFlag.forceDeselection.value,
      PkgFlag.autoSelection.value | PkgFlag.forceDeselection.value:
          PkgFlag.autoSelection.value | PkgFlag.userSelection.value,
      7: PkgFlag.autoSelection.value | PkgFlag.userSelection.value,
    };

    for (final entry in cases.entries) {
      test('flag ${entry.key} -> ${entry.value}', () {
        expect(invertSelectionFlag(entry.key), entry.value);
      });
    }

    test('结果永不置零（不会凭空删行）', () {
      for (var flag = 0; flag <= 7; flag++) {
        expect(invertSelectionFlag(flag), isNot(0), reason: 'flag=$flag');
      }
    });

    test('结果永不同时置 userSelection 与 forceDeselection', () {
      for (var flag = 0; flag <= 7; flag++) {
        final next = invertSelectionFlag(flag);
        expect(
          PkgFlag.userSelection.check(next) && PkgFlag.forceDeselection.check(next),
          isFalse,
          reason: 'flag=$flag -> $next',
        );
      }
    });

    test('保留 autoSelection 位（反选只动用户选择）', () {
      for (var flag = 0; flag <= 7; flag++) {
        expect(
          PkgFlag.autoSelection.check(invertSelectionFlag(flag)),
          PkgFlag.autoSelection.check(flag),
          reason: 'flag=$flag',
        );
      }
    });

    test('纯用户态 1/2 与 auto 态 5/6 上是自反的', () {
      for (final flag in [PkgFlag.userSelection.value, PkgFlag.forceDeselection.value]) {
        expect(invertSelectionFlag(invertSelectionFlag(flag)), flag, reason: 'flag=$flag');
      }
      final autoUser = PkgFlag.autoSelection.value | PkgFlag.userSelection.value;
      final autoForce = PkgFlag.autoSelection.value | PkgFlag.forceDeselection.value;
      expect(invertSelectionFlag(invertSelectionFlag(autoUser)), autoUser);
      expect(invertSelectionFlag(invertSelectionFlag(autoForce)), autoForce);
    });

    test('可见勾选态被翻转', () {
      for (var flag = 0; flag <= 7; flag++) {
        final before = PkgFlag.checkboxValue(flag);
        final after = PkgFlag.checkboxValue(invertSelectionFlag(flag));
        switch (before) {
          case true:
            expect(after, isFalse, reason: 'flag=$flag');
          case false:
            expect(after, isTrue, reason: 'flag=$flag');
          case null:
            // 未选中的（含 auto-only 的三态 indeterminate）反选后一律选中
            expect(after, isTrue, reason: 'flag=$flag');
        }
      }
    });
  });
}
