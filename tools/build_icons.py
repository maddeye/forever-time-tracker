#!/usr/bin/env python3
"""Builds every icon from one description. Needs Pillow and a Chromium-based browser.

    python3 tools/build_icons.py brave

Writes assets/icon.svg, assets/icon.png (CurseForge logo) and
ForeverTimeTracker/Media/icon.tga (in-game: 32-bit, uncompressed, power-of-two).
"""
import math
import os
import subprocess
import sys
import tempfile

from PIL import Image

SIZE = 512
SURFACE = "#1a1a19"
INK = "#f0efec"
# Hues and order match ns.CATEGORIES in Core.lua. Grey stands for idle, AFK and loading.
SHARES = [(30, "#3987e5"), (28, "#d95926"), (11, "#199e70"), (11, "#c98500"), (8, "#d55181"), (12, "#8f8e85")]


def ring(cx, cy, radius, width, gap_degrees):
    parts, angle = [], -90.0
    for share, color in SHARES:
        sweep = share / 100 * 360
        start = math.radians(angle + gap_degrees / 2)
        end = math.radians(angle + sweep - gap_degrees / 2)
        x1, y1 = cx + radius * math.cos(start), cy + radius * math.sin(start)
        x2, y2 = cx + radius * math.cos(end), cy + radius * math.sin(end)
        large = 1 if sweep - gap_degrees > 180 else 0
        parts.append(
            f'<path d="M{x1:.1f} {y1:.1f}A{radius} {radius} 0 {large} 1 {x2:.1f} {y2:.1f}" '
            f'stroke="{color}" stroke-width="{width}" fill="none"/>'
        )
        angle += sweep
    return "".join(parts)


def hand(cx, cy, length, width):
    angle = math.radians(-90 + 52)
    x, y = cx + length * math.cos(angle), cy + length * math.sin(angle)
    return (
        f'<line x1="{cx}" y1="{cy}" x2="{x:.1f}" y2="{y:.1f}" stroke="{INK}" '
        f'stroke-width="{width}" stroke-linecap="round"/>'
        f'<circle cx="{cx}" cy="{cy}" r="{width * 0.95:.1f}" fill="{INK}"/>'
    )


def logo_svg():
    cx, cy = 256, 284
    crown = (
        f'<rect x="212" y="52" width="88" height="34" rx="12" fill="{INK}"/>'
        f'<rect x="240" y="80" width="32" height="40" fill="{INK}"/>'
    )
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">'
        f'<rect width="{SIZE}" height="{SIZE}" rx="104" fill="{SURFACE}"/>'
        f"{crown}{ring(cx, cy, 146, 58, 4)}{hand(cx, cy, 82, 20)}</svg>"
    )


def ingame_svg():
    # A round disc with no crown: it sits inside the minimap button's ring at about 18px,
    # so the marks are heavier and the gaps wider than on the logo.
    c = SIZE / 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">'
        f'<circle cx="{c}" cy="{c}" r="{c}" fill="{SURFACE}"/>'
        f"{ring(c, c, 182, 104, 5)}{hand(c, c, 96, 34)}</svg>"
    )


def rasterize(svg, size, browser):
    with tempfile.TemporaryDirectory() as folder:
        page = os.path.join(folder, "icon.html")
        shot = os.path.join(folder, "icon.png")
        with open(page, "w") as file:
            file.write(f'<!doctype html><body style="margin:0;background:transparent">'
                       f'<div style="width:{SIZE}px;height:{SIZE}px">{svg}</div>')
        subprocess.run(
            [browser, "--headless", "--disable-gpu", "--no-sandbox", "--hide-scrollbars",
             f"--window-size={SIZE},{SIZE}", "--default-background-color=00000000",
             f"--screenshot={shot}", f"file://{page}"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60,
        )
        image = Image.open(shot).convert("RGBA")
        image.load()
    return image.resize((size, size), Image.LANCZOS)


def main():
    browser = sys.argv[1]
    logo = logo_svg()
    with open("assets/icon.svg", "w") as file:
        file.write(logo + "\n")
    rasterize(logo, SIZE, browser).save("assets/icon.png")
    os.makedirs("ForeverTimeTracker/Media", exist_ok=True)
    rasterize(ingame_svg(), 64, browser).save("ForeverTimeTracker/Media/icon.tga", compression=None)


if __name__ == "__main__":
    main()
