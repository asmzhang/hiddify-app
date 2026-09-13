#!/bin/sh
# ---------------------------------------------------------------------------
# doctor 辅助脚本：核对 Go 模块缓存是否「真的可用」。
#
# 判定方法
#   go 把 @v/<ver>.info 当作「这个版本已下载」的凭证之一。缺了它，go 就认为
#   该版本从没下载过，于是解析这个模块的包时转去查 @latest —— 抓到一个要求
#   `go >= 1.26.x` 的新版本，然后直接报：
#       go: toolchain upgrade needed to resolve <package>
#   本仓库踩过这个坑：gvisor.dev/gvisor、metacubex/utls、psiphon-tunnel-core、
#   gonum 的 .info 都不见了（半途中断的下载留下的）。因为 .mod/.zip 还在，
#   表面完全看不出问题，报错又指向"版本不对"，极易误判。
#
# 检查范围
#   只看「已经解压过」的模块（$GOMODCACHE/<mod>@<ver> 目录存在）。
#   从没下载过的模块不算问题 —— go 需要时会自己去下。
#   注意：只查 .info 缺失这一种损坏；解压到一半（文件不全但 .info 在）查不出来，
#   那种情况只能用 `go clean -modcache` 兜底。
#
# 实现约束
#   纯内建 + 1 个 find，循环里不 spawn 任何外部进程 —— 否则在 Windows 上
#   每个模块 0.2s，几百个模块要跑两分钟。
#
# 用法: sh scripts/doctor_go_cache.sh
# 退出码: 0=OK  1=发现问题  2=无法检查（跳过，不算失败）
# ---------------------------------------------------------------------------
set -u

command -v go >/dev/null 2>&1 || { echo "    SKIP go module cache   - go is not in PATH"; exit 2; }

MC="$(go env GOMODCACHE 2>/dev/null || true)"
if [ -z "$MC" ] || [ ! -d "$MC" ]; then
    echo "    SKIP go module cache   - GOMODCACHE is not accessible"
    exit 2
fi

cd "$MC" 2>/dev/null || { echo "    SKIP go module cache   - cannot enter $MC"; exit 2; }

TOTAL=0
N=0
BAD=""

# ./<esc-module-path>@<version> —— 缓存里的目录名已经是转义过的形式
# （大写 -> !小写，如 Psiphon-Labs -> !psiphon-!labs），所以直接拿来当路径用。
while IFS= read -r d; do
    [ -n "${d:-}" ] || continue
    rel="${d#./}"
    escmod="${rel%@*}"
    ver="${rel##*@}"
    TOTAL=$((TOTAL + 1))
    if [ ! -f "cache/download/$escmod/@v/$ver.info" ]; then
        N=$((N + 1))
        BAD="$BAD
$escmod@$ver"
    fi
done <<EOF
$(find . -maxdepth 4 -type d -name '*@*' -not -path './cache/*' 2>/dev/null)
EOF

if [ "$TOTAL" = "0" ]; then
    echo "    SKIP go module cache   - no extracted modules yet (nothing to check)"
    exit 2
fi

if [ "$N" = "0" ]; then
    echo "    OK   go module cache   - $TOTAL extracted modules, all have their @v/<ver>.info"
    exit 0
fi

echo "    FAIL go module cache   - $N of $TOTAL extracted modules lack @v/<ver>.info:"
printf '%s\n' "$BAD" | grep . | head -n 6 | while IFS= read -r l; do echo "           $l"; done
[ "$N" -gt 6 ] && echo "           ... and $((N - 6)) more"
echo "         (!x in a path means uppercase X - that is go's module-name escaping)"
echo "         effect: go treats them as 'not downloaded', re-resolves @latest,"
echo "                 then dies with 'requires go >= 1.26.x'"
echo "         fix   : go clean -modcache        (then re-run this doctor)"
exit 1
