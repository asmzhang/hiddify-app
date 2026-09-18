# 预建 Flutter 插件 junction（绕过沙箱内 Dart Link.createSync 失败的问题）。
# flutter_tools 对已存在链接直接跳过（flutter_plugins.dart:1139），junction 也算 link。
# 用法：powershell -File tool/ensure_plugin_junctions.ps1
# 每次新插件加入或 pub get 清掉 .plugin_symlinks 后重跑一次。
$ErrorActionPreference = 'Stop'
$deps = Get-Content "S:\test\1\hiddify-app\.flutter-plugins-dependencies" -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($platform in @('windows', 'linux')) {
    $plugins = $deps.plugins.$platform
    if ($null -eq $plugins) { continue }
    $dir = "S:\test\1\hiddify-app\$platform\flutter\ephemeral\.plugin_symlinks"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $created = 0; $exists = 0
    foreach ($p in $plugins) {
        $link = Join-Path $dir $p.name
        if (Test-Path $link) { $exists++; continue }
        New-Item -ItemType Junction -Path $link -Target $p.path | Out-Null
        $created++
    }
    Write-Output "${platform}: plugins=$($plugins.Count) created=$created exists=$exists"
}
Write-Output "junctions ready"
