#!/usr/bin/env python3
"""Generate the Veil app icon as PNG directly using Pillow.

Produces 1024x1024 PNGs with three translucent elliptical shapes fanning
out from a shared base point, implying a V silhouette.
"""

import math
from PIL import Image, ImageDraw


SIZE = 8192  # render at 8x, then downsample with sips for anti-aliasing
FINAL_SIZE = 1024

# --- Variants (color intensity levels) ---
VARIANTS = {
    "icon-v1-subtle.png": {
        "bg": (232, 233, 237),
        "colors": [(184, 169, 212), (196, 177, 222), (209, 188, 230)],
        "opacities": [0.45, 0.40, 0.35],
    },
    "icon-v2-medium.png": {
        "bg": (232, 233, 237),
        "colors": [(150, 115, 200), (170, 135, 215), (190, 155, 228)],
        "opacities": [0.60, 0.52, 0.45],
    },
    "icon-v3-vivid.png": {
        "bg": (232, 233, 237),
        "colors": [(130, 85, 195), (150, 105, 210), (172, 128, 225)],
        "opacities": [0.70, 0.60, 0.52],
    },
    "icon-v4-bold.png": {
        "bg": (232, 233, 237),
        "colors": [(115, 65, 190), (135, 85, 205), (158, 110, 220)],
        "opacities": [0.80, 0.68, 0.58],
    },
    "icon-v5-deep.png": {
        "bg": (232, 233, 237),
        "colors": [(100, 50, 180), (120, 70, 198), (145, 95, 215)],
        "opacities": [0.85, 0.75, 0.65],
    },
}

# --- Petal geometry ---
BASE_X_RATIO = 0.50
BASE_Y_RATIO = 0.78
PETAL_RX_RATIO = 0.09
PETAL_RY_RATIO = 0.38
PETAL_OFFSET_RATIO = 0.30
ANGLES_DEG = [-22, 0, 22]


def draw_ellipse_rotated(canvas, cx, cy, rx, ry, angle_deg, pivot_x, pivot_y, color_rgba):
    """Draw a filled rotated ellipse by compositing a rotated layer."""
    margin = int(max(rx, ry) * 2)
    tmp_size = margin * 2
    tmp = Image.new("RGBA", (tmp_size, tmp_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(tmp)

    tcx, tcy = tmp_size // 2, tmp_size // 2
    draw.ellipse(
        [tcx - rx, tcy - ry, tcx + rx, tcy + ry],
        fill=color_rgba,
    )

    pivot_in_tmp_x = pivot_x - cx + tcx
    pivot_in_tmp_y = pivot_y - cy + tcy

    angle_rad = math.radians(-angle_deg)
    cos_a = math.cos(angle_rad)
    sin_a = math.sin(angle_rad)

    a = cos_a
    b = sin_a
    c = pivot_in_tmp_x - cos_a * pivot_in_tmp_x - sin_a * pivot_in_tmp_y
    d = -sin_a
    e = cos_a
    f = pivot_in_tmp_y + sin_a * pivot_in_tmp_x - cos_a * pivot_in_tmp_y

    tmp_rotated = tmp.transform(tmp.size, Image.AFFINE, (a, b, c, d, e, f), resample=Image.BICUBIC)

    paste_x = int(cx - tcx)
    paste_y = int(cy - tcy)
    canvas.alpha_composite(tmp_rotated, (paste_x, paste_y))


def generate_icon(filename, bg, colors, opacities):
    img = Image.new("RGBA", (SIZE, SIZE), (*bg, 255))

    base_x = SIZE * BASE_X_RATIO
    base_y = SIZE * BASE_Y_RATIO
    petal_rx = SIZE * PETAL_RX_RATIO
    petal_ry = SIZE * PETAL_RY_RATIO
    petal_offset = SIZE * PETAL_OFFSET_RATIO

    for angle, color, opacity in zip(ANGLES_DEG, colors, opacities):
        cx = base_x
        cy = base_y - petal_offset
        pivot_x = cx
        pivot_y = cy + petal_ry

        alpha = int(opacity * 255)
        color_rgba = (*color, alpha)

        draw_ellipse_rotated(img, cx, cy, petal_rx, petal_ry, angle,
                             pivot_x, pivot_y, color_rgba)

    # Save hi-res, then downsample with sips for clean anti-aliasing
    hires = filename.replace(".png", "-hires.png")
    img.save(hires, "PNG")

    import subprocess
    subprocess.run([
        "/usr/bin/sips",
        "-s", "format", "png",
        "-z", str(FINAL_SIZE), str(FINAL_SIZE),
        hires, "--out", filename,
    ], check=True, capture_output=True)

    import os
    os.remove(hires)

    print(f"Written {filename}")


if __name__ == "__main__":
    for filename, params in VARIANTS.items():
        generate_icon(filename, **params)
