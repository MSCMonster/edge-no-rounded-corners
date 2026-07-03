# 一键去除 Microsoft Edge 网页内容区的强制圆角样式
# One-click removal of Microsoft Edge's forced rounded corners on web content
#
# 原理: 以下命令行特性开关的优先级高于微软服务端实验推送, 脚本将其注入 Edge 的所有启动入口
# (快捷方式 / 开机预启动项 / 协议关联命令), 使其在任何启动方式下都生效:
#   --enable-features=msForceNoRoundedCornerAndMargin
#   --disable-features=msVisualRejuvRounding
#
# 用法 Usage (建议管理员 PowerShell / run as Administrator):
#   .\edge_no_rounded_corner.ps1                # 应用 apply
#   .\edge_no_rounded_corner.ps1 -RestartEdge   # 应用并立即重启 Edge 生效 apply & restart
#   .\edge_no_rounded_corner.ps1 -Undo          # 撤销全部修改 revert
#
# 注意: 本文件必须以 UTF-8 with BOM 编码保存, 否则 Windows PowerShell 5.1 下中文会乱码
param([switch]$Undo, [switch]$RestartEdge)

# 按系统界面语言选择输出文本, 兜底英语
$lang = switch -Regex ([System.Globalization.CultureInfo]::CurrentUICulture.Name) {
    '^zh' { 'zh' }
    '^ja' { 'ja' }
    default { 'en' }
}
$T = (@{
    zh = @{
        Patched = '已修改'; Reverted = '已撤销'; AlreadyOk = '无需修改'; Failed = '修改失败'
        NeedAdmin = '(需要管理员权限)'; MaybePerm = '(权限不足?)'
        Startup = '自启动项'; Protocol = '协议命令'
        Restarted = 'Edge 已重启并恢复会话'
        ExeNotFound = '未找到 msedge.exe, 请手动重启 Edge'
        Done = '完成。'
    }
    ja = @{
        Patched = '変更しました'; Reverted = '元に戻しました'; AlreadyOk = '変更不要'; Failed = '変更に失敗しました'
        NeedAdmin = '（管理者権限が必要）'; MaybePerm = '（権限不足の可能性）'
        Startup = '自動起動エントリ'; Protocol = 'プロトコルコマンド'
        Restarted = 'Edge を再起動し、セッションを復元しました'
        ExeNotFound = 'msedge.exe が見つかりません。Edge を手動で再起動してください'
        Done = '完了。'
    }
    en = @{
        Patched = 'Patched'; Reverted = 'Reverted'; AlreadyOk = 'Already OK'; Failed = 'Failed'
        NeedAdmin = '(administrator rights required)'; MaybePerm = '(insufficient permissions?)'
        Startup = 'startup entry'; Protocol = 'protocol command'
        Restarted = 'Edge restarted with session restored'
        ExeNotFound = 'msedge.exe not found, please restart Edge manually'
        Done = 'Done.'
    }
})[$lang]

$flags  = '--enable-features=msForceNoRoundedCornerAndMargin --disable-features=msVisualRejuvRounding'
$marker = 'msForceNoRoundedCornerAndMargin'

# 在带引号的 msedge.exe 命令串中插入/移除参数
function Edit-Command([string]$v) {
    if ($Undo) { return $v.Replace(" $flags", '') }
    return $v.Replace('msedge.exe"', "msedge.exe`" $flags")
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
        try {
            if ($Undo) {
                if ($cur -like "*$marker*") { $lnk.Arguments = $cur.Replace($flags, '').Trim(); $lnk.Save(); "$($T.Reverted): $($f.FullName)" }
            } elseif ($cur -notlike "*$marker*") {
                $lnk.Arguments = "$flags $cur".Trim(); $lnk.Save(); "$($T.Patched): $($f.FullName)"
            } else { "$($T.AlreadyOk): $($f.FullName)" }
        } catch { "$($T.Failed) $($T.MaybePerm): $($f.FullName)" }
    }
}

# --- 2. 开机预启动项 (startup boost): 不改这里, 开机常驻的 Edge 进程会让参数失效 ---
foreach ($rk in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    if (-not (Test-Path $rk)) { continue }
    foreach ($name in ((Get-Item $rk).GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })) {
        $v = (Get-ItemProperty $rk -Name $name).$name
        $need = if ($Undo) { $v -like "*$marker*" } else { $v -notlike "*$marker*" }
        if (-not $need) { "$($T.AlreadyOk): $($T.Startup) $name"; continue }
        try {
            Set-ItemProperty $rk -Name $name -Value (Edit-Command $v) -ErrorAction Stop
            "$(if ($Undo) { $T.Reverted } else { $T.Patched }): $($T.Startup) $name"
        } catch { "$($T.Failed): $($T.Startup) $name - $($_.Exception.Message)" }
    }
}

# --- 3. 协议关联命令: 外部程序点击链接冷启动 Edge 时使用 (需管理员权限) ---
foreach ($cls in @('MSEdgeHTM', 'microsoft-edge')) {
    $key = "Registry::HKEY_CLASSES_ROOT\$cls\shell\open\command"
    if (-not (Test-Path $key)) { continue }
    $v = (Get-ItemProperty $key).'(default)'
    $need = if ($Undo) { $v -like "*$marker*" } else { $v -notlike "*$marker*" }
    if (-not $need) { "$($T.AlreadyOk): $($T.Protocol) $cls"; continue }
    try {
        Set-ItemProperty $key -Name '(default)' -Value (Edit-Command $v) -ErrorAction Stop
        "$(if ($Undo) { $T.Reverted } else { $T.Patched }): $($T.Protocol) $cls"
    } catch { "$($T.Failed) $($T.NeedAdmin): $($T.Protocol) $cls" }
}

# --- 4. 可选: 立即重启 Edge 使参数生效 ---
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
