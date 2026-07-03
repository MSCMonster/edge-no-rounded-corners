# 一键去除 Microsoft Edge 网页内容区的强制圆角样式
# One-click removal of Microsoft Edge's forced rounded corners on web content
#
# 原理: 以下命令行特性开关的优先级高于微软服务端实验推送, 脚本将其注入 Edge 的所有启动入口:
#   --enable-features=msForceNoRoundedCornerAndMargin
#   --disable-features=msVisualRejuvRounding
# 但 Chromium 只认"第一个浏览器主进程"的命令行: 开机后若存在一个不带参数的 Edge 常驻进程
# (startup boost 预启动 / Windows 登录后自动恢复的应用), 点击任何入口都只是让它开新窗口,
# 注入的参数不会被读取; 且 startup boost 的自启动项由 Edge 自行管理, 注入的参数会在 Edge
# 运行期间被重写回默认值。因此脚本还会通过组策略 StartupBoostEnabled=0 禁用预启动, 治本。
#
# 用法 Usage (建议管理员 PowerShell / run as Administrator):
#   .\edge_no_rounded_corner.ps1                      # 应用 apply
#   .\edge_no_rounded_corner.ps1 -RestartEdge         # 应用并立即重启 Edge 生效 apply & restart
#   .\edge_no_rounded_corner.ps1 -DisableRestartApps  # 同时关闭 Windows "重新启动应用"
#   .\edge_no_rounded_corner.ps1 -Undo                # 撤销全部修改 revert
#
# 注意: 本文件必须以 UTF-8 with BOM 编码保存, 否则 Windows PowerShell 5.1 下中文会乱码
param([switch]$Undo, [switch]$RestartEdge, [switch]$DisableRestartApps)

$VERSION = '2.0.0'

# 按系统界面语言选择输出文本, 兜底英语
$lang = switch -Regex ([System.Globalization.CultureInfo]::CurrentUICulture.Name) {
    '^zh' { 'zh' }
    '^ja' { 'ja' }
    default { 'en' }
}
$T = (@{
    zh = @{
        Patched = '已修改'; Reverted = '已撤销'; AlreadyOk = '无需修改'; Failed = '修改失败'
        Updated = '已更新旧版参数'
        NeedAdmin = '(需要管理员权限)'; MaybePerm = '(权限不足?)'
        Startup = '自启动项'; Protocol = '协议命令'; Policy = '启动加速策略'; RestartApps = '登录后重启应用'
        RestartAppsWarn = '警告: Windows "重新启动应用" 处于开启状态, 系统重启后自动恢复的 Edge 不带本参数, 圆角会复活(手动重开 Edge 即可消除)。运行时加 -DisableRestartApps 可关闭该功能'
        Restarted = 'Edge 已重启并恢复会话'
        ExeNotFound = '未找到 msedge.exe, 请手动重启 Edge'
        Done = '完成。'
    }
    ja = @{
        Patched = '変更しました'; Reverted = '元に戻しました'; AlreadyOk = '変更不要'; Failed = '変更に失敗しました'
        Updated = '旧バージョンのフラグを更新しました'
        NeedAdmin = '（管理者権限が必要）'; MaybePerm = '（権限不足の可能性）'
        Startup = '自動起動エントリ'; Protocol = 'プロトコルコマンド'; Policy = 'Startup Boost ポリシー'; RestartApps = 'サインイン後のアプリ再起動'
        RestartAppsWarn = '警告: Windows の「アプリの再起動」が有効です。システム再起動後に自動復元される Edge にはフラグが付かず、角丸が復活します（Edge を手動で開き直せば解消）。-DisableRestartApps を付けると無効化できます'
        Restarted = 'Edge を再起動し、セッションを復元しました'
        ExeNotFound = 'msedge.exe が見つかりません。Edge を手動で再起動してください'
        Done = '完了。'
    }
    en = @{
        Patched = 'Patched'; Reverted = 'Reverted'; AlreadyOk = 'Already OK'; Failed = 'Failed'
        Updated = 'Updated stale flags'
        NeedAdmin = '(administrator rights required)'; MaybePerm = '(insufficient permissions?)'
        Startup = 'startup entry'; Protocol = 'protocol command'; Policy = 'startup boost policy'; RestartApps = 'restart apps after sign-in'
        RestartAppsWarn = 'Warning: Windows "restart apps after sign-in" is ON; the Edge instance auto-restored after a reboot carries no flags, so rounded corners come back (reopening Edge manually fixes it). Pass -DisableRestartApps to turn it off'
        Restarted = 'Edge restarted with session restored'
        ExeNotFound = 'msedge.exe not found, please restart Edge manually'
        Done = 'Done.'
    }
})[$lang]

"edge_no_rounded_corner.ps1 v$VERSION"

$flags  = '--enable-features=msForceNoRoundedCornerAndMargin --disable-features=msVisualRejuvRounding'
$marker = 'msForceNoRoundedCornerAndMargin'

# 移除本脚本历史上注入过的所有参数变体; 旧版 disable 参数与当前不同, 仅凭 marker 判断会漏更新
function Remove-OurFlags([string]$v) {
    if (-not $v) { return '' }
    $v = $v -replace '\s*--enable-features=msForceNoRoundedCornerAndMargin\b', ''
    $v = $v -replace '\s*--disable-features=(msVisualRejuvRounding|msOmniboxFocusRingRoundEmphasize)\b', ''
    return $v.Trim()
}

# 在带引号的 msedge.exe 命令串中插入/移除参数
function Edit-Command([string]$v) {
    $clean = Remove-OurFlags $v
    if ($Undo) { return $clean }
    return $clean.Replace('msedge.exe"', "msedge.exe`" $flags")
}

# 根据"改前是否已含 marker"选择动作文本: 已含 → 更新旧参数, 未含 → 首次注入
function Get-ActionText([string]$old) {
    if ($Undo) { return $T.Reverted }
    if ($old -like "*$marker*") { return $T.Updated }
    return $T.Patched
}

$edgeExe = $null

# --- 1. 快捷方式: 桌面(用户/公共) + 任务栏固定 + 开始菜单(用户/公共) ---
$dirs = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonDesktopDirectory'),
    "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar",
    [Environment]::GetFolderPath('Programs'),
    [Environment]::GetFolderPath('CommonPrograms')
) | Where-Object { $_ -and (Test-Path $_) }
$sh = New-Object -ComObject WScript.Shell
foreach ($d in $dirs) {
    foreach ($f in (Get-ChildItem $d -Filter *.lnk -Recurse -ErrorAction SilentlyContinue)) {
        $lnk = $sh.CreateShortcut($f.FullName)
        if ($lnk.TargetPath -notlike '*msedge.exe') { continue }
        $edgeExe = $lnk.TargetPath
        $cur = $lnk.Arguments
        $clean = Remove-OurFlags $cur
        $want = if ($Undo) { $clean } else { "$flags $clean".Trim() }
        if ($cur -eq $want) { "$($T.AlreadyOk): $($f.FullName)"; continue }
        try {
            $lnk.Arguments = $want; $lnk.Save()
            "$(Get-ActionText $cur): $($f.FullName)"
        } catch { "$($T.Failed) $($T.MaybePerm): $($f.FullName)" }
    }
}

# --- 2. 开机预启动项 (startup boost): 尽力注入; 该项由 Edge 自行管理, 参数会在运行期被收回,
#        根治依赖第 4 步的组策略(策略生效后 Edge 会自行删除此项) ---
foreach ($rk in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    if (-not (Test-Path $rk)) { continue }
    foreach ($name in ((Get-Item $rk).GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })) {
        $v = (Get-ItemProperty $rk -Name $name).$name
        $want = Edit-Command $v
        if ($v -eq $want) { "$($T.AlreadyOk): $($T.Startup) $name"; continue }
        try {
            Set-ItemProperty $rk -Name $name -Value $want -ErrorAction Stop
            "$(Get-ActionText $v): $($T.Startup) $name"
        } catch { "$($T.Failed): $($T.Startup) $name - $($_.Exception.Message)" }
    }
}

# --- 3. 协议关联命令: 外部程序点击链接冷启动 Edge 时使用 (需管理员权限) ---
foreach ($cls in @('MSEdgeHTM', 'microsoft-edge')) {
    $key = "Registry::HKEY_CLASSES_ROOT\$cls\shell\open\command"
    if (-not (Test-Path $key)) { continue }
    $v = (Get-ItemProperty $key).'(default)'
    $want = Edit-Command $v
    if ($v -eq $want) { "$($T.AlreadyOk): $($T.Protocol) $cls"; continue }
    try {
        Set-ItemProperty $key -Name '(default)' -Value $want -ErrorAction Stop
        "$(Get-ActionText $v): $($T.Protocol) $cls"
    } catch { "$($T.Failed) $($T.NeedAdmin): $($T.Protocol) $cls" }
}

# --- 4. Startup Boost 组策略: 治本关键。开机预启动的"无参数常驻进程"会让所有入口的参数失效,
#        且第 2 步注入的参数会被 Edge 收回, 只有禁用预启动才能保证冷启动永远走带参数的入口 ---
$polKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
$polVal = (Get-ItemProperty $polKey -Name StartupBoostEnabled -ErrorAction SilentlyContinue).StartupBoostEnabled
if ($Undo) {
    if ($null -eq $polVal) { "$($T.AlreadyOk): $($T.Policy)" }
    else {
        try {
            Remove-ItemProperty $polKey -Name StartupBoostEnabled -ErrorAction Stop
            "$($T.Reverted): $($T.Policy) StartupBoostEnabled"
        } catch { "$($T.Failed) $($T.NeedAdmin): $($T.Policy)" }
    }
} elseif ($polVal -eq 0) { "$($T.AlreadyOk): $($T.Policy)" }
else {
    try {
        if (-not (Test-Path $polKey)) { New-Item $polKey -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty $polKey -Name StartupBoostEnabled -Value 0 -Type DWord -ErrorAction Stop
        "$($T.Patched): $($T.Policy) StartupBoostEnabled=0"
    } catch { "$($T.Failed) $($T.NeedAdmin): $($T.Policy)" }
}

# --- 5. Windows "重新启动应用": 系统重启后自动恢复的 Edge 同样不带参数。这是影响所有应用的
#        系统级偏好, 默认只检测提示, 加 -DisableRestartApps 才关闭; -Undo 不自动恢复 ---
$wlKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon'
$ra = (Get-ItemProperty $wlKey -Name RestartApps -ErrorAction SilentlyContinue).RestartApps
if (-not $Undo -and $ra -eq 1) {
    if ($DisableRestartApps) {
        try {
            Set-ItemProperty $wlKey -Name RestartApps -Value 0 -Type DWord -ErrorAction Stop
            "$($T.Patched): $($T.RestartApps) RestartApps=0"
        } catch { "$($T.Failed): $($T.RestartApps)" }
    } else { $T.RestartAppsWarn }
}

# --- 6. 可选: 立即重启 Edge 使参数生效 ---
if ($RestartEdge) {
    $procs = Get-Process msedge -ErrorAction SilentlyContinue
    if ($procs) {
        # 先向主窗口发送正常关闭消息, 保证会话被保存, 超时后再强制结束残留进程
        $procs | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { $null = $_.CloseMainWindow() }
        $deadline = (Get-Date).AddSeconds(15)
        while ((Get-Process msedge -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -Confirm:$false
        Start-Sleep -Seconds 2
    }
    if (-not $edgeExe) {
        $edgeExe = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\msedge.exe' -ErrorAction SilentlyContinue).'(default)'
    }
    if ($edgeExe -and (Test-Path $edgeExe)) {
        $restartArgs = if ($Undo) { '--restore-last-session' } else { "$flags --restore-last-session" }
        Start-Process $edgeExe -ArgumentList $restartArgs
        $T.Restarted
    } else { $T.ExeNotFound }
}

$T.Done
