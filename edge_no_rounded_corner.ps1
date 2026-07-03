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
param([switch]$Undo, [switch]$RestartEdge)

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
                if ($cur -like "*$marker*") { $lnk.Arguments = $cur.Replace($flags, '').Trim(); $lnk.Save(); "已撤销 reverted: $($f.FullName)" }
            } elseif ($cur -notlike "*$marker*") {
                $lnk.Arguments = "$flags $cur".Trim(); $lnk.Save(); "已修改 patched: $($f.FullName)"
            } else { "无需修改 already ok: $($f.FullName)" }
        } catch { "修改失败 failed (是否缺少权限?): $($f.FullName)" }
    }
}

# --- 2. 开机预启动项 (startup boost): 不改这里, 开机常驻的 Edge 进程会让参数失效 ---
foreach ($rk in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
    if (-not (Test-Path $rk)) { continue }
    foreach ($name in ((Get-Item $rk).GetValueNames() | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch*' })) {
        $v = (Get-ItemProperty $rk -Name $name).$name
        $need = if ($Undo) { $v -like "*$marker*" } else { $v -notlike "*$marker*" }
        if (-not $need) { "无需修改 already ok: 自启动项 $name"; continue }
        try { Set-ItemProperty $rk -Name $name -Value (Edit-Command $v) -ErrorAction Stop; "已处理 done: 自启动项 startup entry $name" }
        catch { "修改失败 failed: 自启动项 $name - $($_.Exception.Message)" }
    }
}

# --- 3. 协议关联命令: 外部程序点击链接冷启动 Edge 时使用 (需管理员权限) ---
foreach ($cls in @('MSEdgeHTM', 'microsoft-edge')) {
    $key = "Registry::HKEY_CLASSES_ROOT\$cls\shell\open\command"
    if (-not (Test-Path $key)) { continue }
    $v = (Get-ItemProperty $key).'(default)'
    $need = if ($Undo) { $v -like "*$marker*" } else { $v -notlike "*$marker*" }
    if (-not $need) { "无需修改 already ok: 协议命令 $cls"; continue }
    try { Set-ItemProperty $key -Name '(default)' -Value (Edit-Command $v) -ErrorAction Stop; "已处理 done: 协议命令 protocol $cls" }
    catch { "修改失败 failed (需要管理员权限 admin required): 协议命令 $cls" }
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
        "Edge 已重启并恢复会话 restarted with session restored"
    } else { "未找到 msedge.exe, 请手动重启 Edge / msedge.exe not found, restart Edge manually" }
}

"完成 done."
