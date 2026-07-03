# edge-no-rounded-corners

一键去除 Microsoft Edge 强制开启的网页内容区圆角样式。
One-click removal of the rounded web-content corners that Microsoft Edge force-enables.
Microsoft Edge が強制的に有効化する Web ページ角丸スタイルをワンクリックで無効化。

[简体中文](#简体中文) | [日本語](#日本語) | [English](#english)

![圆角效果示例 / Example of the rounded corner](docs/rounded-corner-example.png)

---

## 简体中文

### 问题背景

自 Edge 149 前后起，微软通过**服务端实验推送**（Controlled Feature Rollout）向部分用户强制开启"网页内容区圆角 + 四周边距"的视觉样式（内部特性名 `msVisualRejuvRounding`，属于 Phoenix 视觉改版的一部分）。该推送具有以下特点：

- `edge://flags` 中没有对应的开关条目（`edge-force-no-rounded-corner-and-margin` 未在正式版注册，写入 `Local State` 会被启动时清除）
- 设置页面没有开关；直接把相关设置项（`browser.show_edge_frames_as_rounded`、`phoenix.rounded_frame_enabled`）写为 `false` 也会被服务端实验覆盖，不生效

经实测，唯一可靠的手段是**命令行特性开关**，其优先级高于服务端推送：

```
--enable-features=msForceNoRoundedCornerAndMargin --disable-features=msVisualRejuvRounding
```

### 脚本做了什么

`edge_no_rounded_corner.ps1` 把上述参数注入 Edge 的**所有启动入口**，保证无论从哪里启动都生效：

| 启动入口 | 说明 |
|---|---|
| 桌面快捷方式（用户/公共） | 双击图标启动 |
| 任务栏固定图标 | 任务栏启动 |
| 开始菜单快捷方式（用户/公共） | 开始菜单/搜索启动 |
| 开机预启动项（startup boost） | **关键**：不改这里，开机常驻的 Edge 进程会让其他入口的参数全部失效 |
| `MSEdgeHTM` / `microsoft-edge` 协议命令 | 从其他程序点击链接冷启动 Edge |

### 使用方法

以管理员身份打开 PowerShell：

```powershell
irm https://raw.githubusercontent.com/MSCMonster/edge-no-rounded-corners/main/edge_no_rounded_corner.ps1 -OutFile "$env:TEMP\edge_no_rounded_corner.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\edge_no_rounded_corner.ps1" -RestartEdge
```

- `-RestartEdge`：应用后立即优雅重启 Edge（先正常关闭保存会话，重启时恢复标签页）；不加则下次启动生效
- `-Undo`：撤销全部修改

> **备用方式**：部分网络环境下 `raw.githubusercontent.com` 无法解析（提示"未能解析此远程名称"），这不是设备问题。此时改用 github.com 的 ZIP 下载通道：
>
> ```powershell
> irm https://github.com/MSCMonster/edge-no-rounded-corners/archive/refs/heads/main.zip -OutFile "$env:TEMP\enrc.zip"
> Expand-Archive "$env:TEMP\enrc.zip" "$env:TEMP\enrc" -Force
> powershell -ExecutionPolicy Bypass -File "$env:TEMP\enrc\edge-no-rounded-corners-main\edge_no_rounded_corner.ps1" -RestartEdge
> ```
>
> 装有 git 的设备也可以直接 `git clone https://github.com/MSCMonster/edge-no-rounded-corners.git` 后运行脚本。

### 检测工具（可选）

`tools/edge_corner_check.py` 可以自动截取 Edge 客户区左下角并通过"等宽边距 + 对角线圆弧签名"判定当前是否处于圆角状态（退出码 0 = 无圆角，1 = 有圆角，2 = 无法判定），适合脚本化验证：

```powershell
pip install pillow
python tools\edge_corner_check.py
```

### 注意事项

- Edge 大版本更新可能重写快捷方式、自启动项和协议注册。若圆角复活，重新运行脚本即可（脚本幂等，可重复执行）
- 协议命令和公共目录的修改需要管理员权限，其余条目普通权限即可
- 实测环境：Edge 149.0.4022.98 / Windows 10 19045（2026-07）。若微软将来更改内部特性名，脚本可能需要更新

---

## 日本語

### 背景

Edge 149 前後から、Microsoft は**サーバー側の実験配信**（Controlled Feature Rollout）により、一部のユーザーに対して「Web コンテンツ領域の角丸 + 余白」という視覚スタイル（内部機能名 `msVisualRejuvRounding`、Phoenix ビジュアル刷新の一部）を強制的に有効化しています。この配信には次の特徴があります。

- `edge://flags` に対応する項目が存在しない（`edge-force-no-rounded-corner-and-margin` は安定版に登録されておらず、`Local State` に書き込んでも起動時に削除される）
- 設定画面にスイッチがなく、関連設定（`browser.show_edge_frames_as_rounded`、`phoenix.rounded_frame_enabled`）を `false` にしてもサーバー側実験に上書きされて効かない

検証の結果、確実に効く唯一の手段は、サーバー側配信より優先される**コマンドライン機能フラグ**です。

```
--enable-features=msForceNoRoundedCornerAndMargin --disable-features=msVisualRejuvRounding
```

### スクリプトの動作

`edge_no_rounded_corner.ps1` は上記フラグを Edge の**すべての起動エントリ**に注入し、どこから起動しても有効になるようにします。

| 起動エントリ | 説明 |
|---|---|
| デスクトップのショートカット（ユーザー/共通） | アイコンから起動 |
| タスクバーにピン留めされたアイコン | タスクバーから起動 |
| スタートメニューのショートカット（ユーザー/共通） | スタートメニュー/検索から起動 |
| 自動起動エントリ（startup boost） | **重要**: ここを変更しないと、ログオン時に常駐する Edge プロセスによって他のエントリのフラグがすべて無効化される |
| `MSEdgeHTM` / `microsoft-edge` プロトコルコマンド | 他のアプリからリンクをクリックしてコールドスタートする場合 |

### 使い方

管理者権限で PowerShell を開き、次を実行します。

```powershell
irm https://raw.githubusercontent.com/MSCMonster/edge-no-rounded-corners/main/edge_no_rounded_corner.ps1 -OutFile "$env:TEMP\edge_no_rounded_corner.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\edge_no_rounded_corner.ps1" -RestartEdge
```

- `-RestartEdge`: 適用後すぐに Edge を正常終了→再起動し、セッション（タブ）を復元します。指定しない場合は次回起動から有効
- `-Undo`: すべての変更を元に戻します

### 検出ツール（任意）

`tools/edge_corner_check.py` は Edge クライアント領域の左下隅を自動キャプチャし、「等幅の余白 + 対角線上の円弧シグネチャ」により角丸の有無を判定します（終了コード 0 = 角丸なし、1 = 角丸あり、2 = 判定不能）。

```powershell
pip install pillow
python tools\edge_corner_check.py
```

### 注意事項

- Edge の大型アップデートでショートカットや自動起動エントリ、プロトコル登録が書き換えられることがあります。角丸が復活した場合はスクリプトを再実行してください（冪等なので何度でも実行できます）
- プロトコルコマンドと共通ディレクトリの変更には管理者権限が必要です
- 検証環境: Edge 149.0.4022.98 / Windows 10 19045（2026-07）。Microsoft が内部機能名を変更した場合、スクリプトの更新が必要になる可能性があります

---

## English

### Background

Starting around Edge 149, Microsoft force-enables a "rounded web-content corners + surrounding margin" visual style (internal feature `msVisualRejuvRounding`, part of the Phoenix visual refresh) for some users via **server-side experiments** (Controlled Feature Rollout). This rollout has the following properties:

- There is no corresponding entry in `edge://flags` (`edge-force-no-rounded-corner-and-margin` is not registered in stable builds; writing it into `Local State` gets pruned on startup)
- There is no settings toggle, and setting the related preferences (`browser.show_edge_frames_as_rounded`, `phoenix.rounded_frame_enabled`) to `false` is overridden by the server-side experiment

In practice, the only reliable lever is the **command-line feature switches**, which take precedence over server-side rollouts:

```
--enable-features=msForceNoRoundedCornerAndMargin --disable-features=msVisualRejuvRounding
```

### What the script does

`edge_no_rounded_corner.ps1` injects the switches above into **every launch entry point** of Edge, so they apply no matter how Edge is started:

| Entry point | Notes |
|---|---|
| Desktop shortcuts (user/public) | Launch by icon |
| Taskbar pinned icon | Launch from taskbar |
| Start Menu shortcuts (user/common) | Launch from Start Menu / search |
| Auto-launch entry (startup boost) | **Critical**: without patching this, the Edge process resident since logon makes flags on all other entries ineffective |
| `MSEdgeHTM` / `microsoft-edge` protocol commands | Cold start via links clicked in other apps |

### Usage

Open an elevated PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/MSCMonster/edge-no-rounded-corners/main/edge_no_rounded_corner.ps1 -OutFile "$env:TEMP\edge_no_rounded_corner.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\edge_no_rounded_corner.ps1" -RestartEdge
```

- `-RestartEdge`: gracefully restarts Edge right away (normal close to save the session, then relaunch with tabs restored); otherwise the change applies on next launch
- `-Undo`: reverts all modifications

### Detection tool (optional)

`tools/edge_corner_check.py` captures the bottom-left corner of the Edge client area (via `PrintWindow`, works even when occluded) and detects the rounded state by the "uniform margin + diagonal arc signature" (exit code 0 = square, 1 = rounded, 2 = inconclusive) — handy for scripted verification:

```powershell
pip install pillow
python tools\edge_corner_check.py
```

### Notes

- Major Edge updates may rewrite shortcuts, the auto-launch entry, and protocol registrations. If the rounded corners come back, just re-run the script (it is idempotent)
- Administrator rights are required for the protocol commands and machine-wide directories; the rest works with normal privileges
- Tested on Edge 149.0.4022.98 / Windows 10 19045 (2026-07). If Microsoft renames the internal features in the future, the script may need updating

---

## License

[MIT](LICENSE)
