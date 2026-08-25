#!/usr/bin/env python3
"""Draw the Stickies app icon and write the AppIcon asset catalogue.

No third-party dependencies: shapes are rendered from signed distance fields
with analytic anti-aliasing, and PNGs are encoded with zlib. Re-run after
changing the palette:

    python3 Tools/generate_icons.py
"""

import json
import math
import os
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPICON = os.path.join(ROOT, "App", "Resources", "Assets.xcassets", "AppIcon.appiconset")

MASTER = 1024

PAPER_TOP = (1.00, 0.949, 0.62)
PAPER_BOTTOM = (0.988, 0.878, 0.42)
FOLD = (0.906, 0.776, 0.29)
INK = (0.28, 0.22, 0.05)


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def rounded_rect_sdf(px, py, cx, cy, half_w, half_h, radius):
    dx = abs(px - cx) - (half_w - radius)
    dy = abs(py - cy) - (half_h - radius)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    inside = min(max(dx, dy), 0.0)
    return outside + inside - radius


def coverage(sdf):
    """Distance in pixels to alpha, giving a one-pixel soft edge."""
    return clamp(0.5 - sdf)


def over(dst, src, alpha):
    return tuple(src[i] * alpha + dst[i] * (1 - alpha) for i in range(3))


def render_master(inset_fraction, corner_fraction, draw_fold):
    """Render the icon at MASTER×MASTER as a list of (r, g, b, a) floats."""
    size = MASTER
    inset = size * inset_fraction
    half = (size - 2 * inset) / 2
    cx = cy = size / 2
    radius = (size - 2 * inset) * corner_fraction

    # The written lines on the note.
    line_left = inset + half * 0.34
    line_right = inset + 2 * half - half * 0.34
    lines = []
    line_height = half * 0.115
    first_y = cy - half * 0.42
    spacing = half * 0.42
    widths = [1.0, 1.0, 0.62]
    for index, width_scale in enumerate(widths):
        y = first_y + spacing * index
        x_end = line_left + (line_right - line_left) * width_scale
        lines.append((line_left, x_end, y, line_height))

    fold_size = half * 0.46
    fold_x = inset + 2 * half
    fold_y = inset + 2 * half

    pixels = []
    for py in range(size):
        y = py + 0.5
        # Vertical paper gradient.
        t = clamp((y - inset) / max(1.0, (2 * half)))
        paper = tuple(PAPER_TOP[i] + (PAPER_BOTTOM[i] - PAPER_TOP[i]) * t for i in range(3))
        # A soft sheen across the top third sells "paper" rather than "square".
        sheen = clamp(1.0 - (y - inset) / (half * 0.75)) * 0.22

        for px in range(size):
            x = px + 0.5
            body = coverage(rounded_rect_sdf(x, y, cx, cy, half, half, radius))
            if body <= 0.0:
                pixels.append((0.0, 0.0, 0.0, 0.0))
                continue

            color = tuple(clamp(paper[i] + sheen) for i in range(3))

            if draw_fold:
                # Half-plane cutting the bottom-right corner.
                fold_d = (fold_x - x) + (fold_y - y) - fold_size
                fold_alpha = coverage(fold_d) * body
                if fold_alpha > 0:
                    color = over(color, FOLD, fold_alpha)

            for x0, x1, ly, lh in lines:
                d = rounded_rect_sdf(
                    x, y,
                    (x0 + x1) / 2, ly,
                    (x1 - x0) / 2, lh / 2,
                    lh / 2,
                )
                a = coverage(d)
                if a > 0:
                    color = over(color, INK, a * 0.82)

            pixels.append((color[0], color[1], color[2], body))
    return pixels


def downsample(pixels, source_size, target_size):
    factor = source_size // target_size
    out = []
    for ty in range(target_size):
        for tx in range(target_size):
            r = g = b = a = 0.0
            for sy in range(ty * factor, (ty + 1) * factor):
                row = sy * source_size
                for sx in range(tx * factor, (tx + 1) * factor):
                    pr, pg, pb, pa = pixels[row + sx]
                    r += pr * pa
                    g += pg * pa
                    b += pb * pa
                    a += pa
            count = factor * factor
            if a > 0:
                out.append((r / a, g / a, b / a, a / count))
            else:
                out.append((0.0, 0.0, 0.0, 0.0))
    return out


def write_png(path, size, pixels):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        base = y * size
        for x in range(size):
            r, g, b, a = pixels[base + x]
            rows.append(int(clamp(r) * 255 + 0.5))
            rows.append(int(clamp(g) * 255 + 0.5))
            rows.append(int(clamp(b) * 255 + 0.5))
            rows.append(int(clamp(a) * 255 + 0.5))

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


MAC_SIZES = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def main():
    os.makedirs(APPICON, exist_ok=True)

    print("rendering iOS master…")
    ios = render_master(inset_fraction=0.0, corner_fraction=0.0, draw_fold=False)
    write_png(os.path.join(APPICON, "icon-ios-1024.png"), MASTER, ios)

    print("rendering macOS master…")
    mac = render_master(inset_fraction=0.095, corner_fraction=0.215, draw_fold=True)

    images = [
        {"filename": "icon-ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}
    ]

    cache = {MASTER: mac}
    for point, scale in MAC_SIZES:
        pixel_size = point * scale
        if pixel_size not in cache:
            cache[pixel_size] = downsample(mac, MASTER, pixel_size)
        name = "icon-mac-%dx%d@%dx.png" % (point, point, scale)
        print("  writing", name)
        write_png(os.path.join(APPICON, name), pixel_size, cache[pixel_size])
        images.append({
            "filename": name,
            "idiom": "mac",
            "scale": "%dx" % scale,
            "size": "%dx%d" % (point, point),
        })

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(APPICON, "Contents.json"), "w") as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")
    print("done")


if __name__ == "__main__":
    main()
