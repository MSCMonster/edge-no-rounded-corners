# -*- coding: utf-8 -*-
"""
检测 Microsoft Edge 网页内容区左下角是否存在圆角样式。

原理:
  Edge 圆角特性开启时, 网页内容四周有一圈浏览器底色边距(约4-8px),
  内容角落呈圆弧; 关闭时内容以直角填满到窗口客户区边缘。
  脚本用 PrintWindow 截取 Edge 客户区左下角 N x N 像素(默认30, 被
  遮挡也能截), 然后从角落出发做三条扫描:
    - 水平扫描(靠上位置): 跳变距离 ≈ 左边距宽 m
    - 垂直扫描(靠右位置): 跳变距离 ≈ 下边距高 m
    - 对角线扫描: 圆弧使跳变距离 ≈ m + 0.29*r, 明显大于 m
  三者构成"圆角签名"; 角落 5x5 颜色不均匀则说明页面内容直达边缘。

依赖: Python 3.8+, Pillow (pip install pillow)

用法:
  python edge_corner_check.py [区域边长]     # 默认 30

退出码: 0 = 无圆角(直角)   1 = 有圆角   2 = 无法判定
"""
import ctypes
import ctypes.wintypes as wt
import os
import sys
import time
from datetime import datetime

from PIL import Image, ImageGrab

# 管道/重定向下强制 UTF-8 输出, 避免中文乱码
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
kernel32 = ctypes.windll.kernel32

REGION = int(sys.argv[1]) if len(sys.argv) > 1 else 30


def find_edge_window():
    """枚举顶层窗口, 返回面积最大的 Edge 主窗口句柄"""
    found = []

    @ctypes.WINFUNCTYPE(wt.BOOL, wt.HWND, wt.LPARAM)
    def cb(hwnd, _):
        if not user32.IsWindowVisible(hwnd):
            return True
        cls = ctypes.create_unicode_buffer(64)
        user32.GetClassNameW(hwnd, cls, 64)
        if cls.value != "Chrome_WidgetWin_1":
            return True
        if user32.GetWindowTextLengthW(hwnd) == 0:
            return True
        pid = wt.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        h = kernel32.OpenProcess(0x1000, False, pid.value)
        if not h:
            return True
        buf = ctypes.create_unicode_buffer(260)
        size = wt.DWORD(260)
        ok = kernel32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size))
        kernel32.CloseHandle(h)
        if not ok or not buf.value.lower().endswith("msedge.exe"):
            return True
        r = wt.RECT()
        user32.GetWindowRect(hwnd, ctypes.byref(r))
        found.append((hwnd, (r.right - r.left) * (r.bottom - r.top)))
        return True

    user32.EnumWindows(cb, 0)
    return max(found, key=lambda x: x[1])[0] if found else None


def capture_window(hwnd):
    """PrintWindow(PW_RENDERFULLCONTENT) 截取整个窗口, 返回 (PIL图像, 窗口左上角屏幕坐标)"""
    r = wt.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(r))
    w, h = r.right - r.left, r.bottom - r.top

    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [("biSize", wt.DWORD), ("biWidth", ctypes.c_long),
                    ("biHeight", ctypes.c_long), ("biPlanes", wt.WORD),
                    ("biBitCount", wt.WORD), ("biCompression", wt.DWORD),
                    ("biSizeImage", wt.DWORD), ("biXPelsPerMeter", ctypes.c_long),
                    ("biYPelsPerMeter", ctypes.c_long), ("biClrUsed", wt.DWORD),
                    ("biClrImportant", wt.DWORD)]

    hdc = user32.GetWindowDC(hwnd)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mem, bmp)
    ok = user32.PrintWindow(hwnd, mem, 2)  # 2 = PW_RENDERFULLCONTENT
    bi = BITMAPINFOHEADER()
    bi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.biWidth, bi.biHeight = w, -h  # 负高度 = 自上而下的行序
    bi.biPlanes, bi.biBitCount, bi.biCompression = 1, 32, 0
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mem, bmp, 0, h, buf, ctypes.byref(bi), 0)
    gdi32.DeleteObject(bmp)
    gdi32.DeleteDC(mem)
    user32.ReleaseDC(hwnd, hdc)
    img = Image.frombuffer("RGB", (w, h), buf, "raw", "BGRX", 0, 1)
    return (img if ok else None), (r.left, r.top)


def client_bottom_left(hwnd, win_origin):
    """返回客户区左下角 REGION 区域: (窗口图像内裁剪框, 屏幕坐标裁剪框)"""
    cr = wt.RECT()
    user32.GetClientRect(hwnd, ctypes.byref(cr))
    pt = wt.POINT(0, 0)
    user32.ClientToScreen(hwnd, ctypes.byref(pt))
    offx, offy = pt.x - win_origin[0], pt.y - win_origin[1]
    box = (offx, offy + cr.bottom - REGION, offx + REGION, offy + cr.bottom)
    sbox = (pt.x, pt.y + cr.bottom - REGION, pt.x + REGION, pt.y + cr.bottom)
    return box, sbox


def cdist(a, b):
    """颜色差: 各通道差的最大值"""
    return max(abs(a[i] - b[i]) for i in range(3))


def block_stats(img, x0, y0, n=5):
    """n x n 区块的平均色与最大离散度"""
    px = [img.getpixel((x, y)) for x in range(x0, x0 + n) for y in range(y0, y0 + n)]
    mean = tuple(sum(p[i] for p in px) // len(px) for i in range(3))
    spread = max(cdist(p, mean) for p in px)
    return mean, spread


def scan(patch, points, ref, tol):
    """沿点序列找第一个与参考色差超过 tol 的位置, 无跳变返回 None"""
    for i, (x, y) in enumerate(points):
        if cdist(patch.getpixel((x, y)), ref) > tol:
            return i
    return None


def main():
    user32.SetProcessDPIAware()
    hwnd = find_edge_window()
    if not hwnd:
        print("未找到 Edge 窗口")
        sys.exit(2)
    if user32.IsIconic(hwnd):
        user32.ShowWindow(hwnd, 9)  # SW_RESTORE
        time.sleep(0.8)

    img, origin = capture_window(hwnd)
    box, sbox = client_bottom_left(hwnd, origin)
    patch = img.crop(box) if img is not None else None
    # PrintWindow 偶尔对硬件加速窗口返回全黑, 此时退回"置前+屏幕截图"
    if patch is None or patch.convert("L").getextrema()[1] < 8:
        user32.SetForegroundWindow(hwnd)
        time.sleep(0.8)
        patch = ImageGrab.grab(bbox=sbox)

    R = patch.width
    corner, corner_spread = block_stats(patch, 0, R - 5)
    K = R * 2 // 3  # 扫描基线位置, 需大于 边距+半径 (约16px)
    tol = 12
    t_h = scan(patch, [(d, R - 1 - K) for d in range(R)], corner, tol)  # 水平→ 得左边距
    t_v = scan(patch, [(K, R - 1 - d) for d in range(R)], corner, tol)  # 垂直↑ 得下边距
    t_d = scan(patch, [(d, R - 1 - d) for d in range(R)], corner, tol)  # 对角线↗

    ts = datetime.now().strftime("%H%M%S")
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), f"corner_{ts}.png")
    patch.resize((R * 8, R * 8), Image.NEAREST).save(out)

    fmt = lambda t: "无跳变" if t is None else f"{t}px"
    print(f"角落 5x5 平均色 RGB{corner}, 离散度 {corner_spread}")
    print(f"跳变距离: 水平 {fmt(t_h)}  垂直 {fmt(t_v)}  对角线 {fmt(t_d)}  (区域 {R}x{R})")
    print(f"放大截图: {out}")

    # 判定
    if corner_spread > 10:
        print("判定: 无圆角 — 角落颜色不均匀, 页面内容直达窗口边缘")
        sys.exit(0)
    sig = (t_h is not None and t_v is not None and t_d is not None
           and 3 <= t_h <= 16 and 3 <= t_v <= 16
           and abs(t_h - t_v) <= 4 and t_d >= max(t_h, t_v) + 2)
    if sig:
        print(f"判定: 有圆角 — 检测到等宽边距(约{t_h}px)和圆弧特征")
        sys.exit(1)
    if (t_h is not None and t_h <= 2) or (t_v is not None and t_v <= 2):
        print("判定: 无圆角 — 内容颜色在窗口边缘处即出现, 无边距")
        sys.exit(0)
    print("判定: 无法判定 — 角落区域颜色过于均匀(页面底色可能与浏览器边框色相同),"
          " 建议切到深色或白底页面后重测, 并查看放大截图人工确认")
    sys.exit(2)


if __name__ == "__main__":
    main()
