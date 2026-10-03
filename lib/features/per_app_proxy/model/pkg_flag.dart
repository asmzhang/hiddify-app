enum PkgFlag {
  userSelection(1 << 0),
  forceDeselection(1 << 1),
  autoSelection(1 << 2);

  final int value;
  const PkgFlag(this.value);

  bool check(int value) => (value & this.value) == this.value;

  int add(int value) {
    int nValue = value;
    if (this == userSelection) {
      nValue = forceDeselection.remove(nValue);
    } else if (this == forceDeselection) {
      nValue = userSelection.remove(nValue);
    }
    return nValue | this.value;
  }

  int remove(int value) => value & ~this.value;

  int toggle(int value) => value ^ this.value;

  static bool? checkboxValue(int flag) => switch (flag) {
    _ when forceDeselection.check(flag) => false,
    _ when autoSelection.check(flag) && !userSelection.check(flag) => null,
    _ when userSelection.check(flag) => true,
    _ => null,
  };
}

/// NekoBox `action_invert_selections`：翻转某包的「可见勾选态」。
///
/// 判据必须是 [PkgFlag.checkboxValue]（`forceDeselection` 优先），而不是
/// [PkgFlag.userSelection] 位：`userSelection | forceDeselection`（3）的可见态是
/// 「未勾选」，按位判据会把它翻成 2 —— 可见态依旧是「未勾选」，等于没翻。
/// 因此：已勾选 → 强制不选（[PkgFlag.forceDeselection]）；
/// 未勾选（含三态不确定态）→ 选上（[PkgFlag.userSelection]）。
/// [PkgFlag.add] 已保证两者互斥。
int invertSelectionFlag(int value) => PkgFlag.checkboxValue(value) == true
    ? PkgFlag.forceDeselection.add(value)
    : PkgFlag.userSelection.add(value);
