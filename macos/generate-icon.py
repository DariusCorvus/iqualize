#!/usr/bin/env python3
"""Generate the iQualize app icon as a macOS .icns file.

Design system sourced from darius-codes: dark ink backgrounds with
ember (#ff6a24) and ice (#6af0d8) accent colors. Five EQ bars with
hard color stops. The "d" favicon from darius.codes rotated -90°
as a half-ring behind the bars.
"""

import os
import subprocess
from PIL import Image, ImageDraw, ImageFilter

# -- Design system colors from darius-codes --
INK_1 = (11, 12, 15)       # #0b0c0f
INK_4 = (34, 38, 47)       # #22262f
INK_5 = (44, 48, 60)       # #2c303c
EMBER = (255, 106, 36)     # #ff6a24
ICE = (106, 240, 216)      # #6af0d8


def rounded_rect_mask(size, radius):
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def quadratic_bezier(p0, p1, p2, steps=64):
    """Generate points along a quadratic bezier curve."""
    points = []
    for i in range(steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0]
        y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1]
        points.append((x, y))
    return points


def render_d_favicon(render_size):
    """Render the darius.codes 'd' favicon SVG at given size.

    Original SVG (viewBox 0 0 36 36):
      <rect x="6" y="6" width="3" height="24" fill="#F07840"/>
      <path d="M9 6 Q24 6 24 18 Q24 30 9 30" stroke="#F07840" stroke-width="3" fill="none"/>
      <rect x="27" y="22" width="3" height="8" fill="#6AF0D8" opacity="0.75"/>
    """
    scale = render_size / 36.0
    img = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    sw = max(round(3 * scale), 1)  # stroke width

    # Stem rectangle
    sx0 = round(6 * scale)
    sx1 = max(sx0 + 1, round(9 * scale) - 1)
    draw.rectangle([sx0, round(6 * scale), sx1, round(30 * scale) - 1], fill=(*INK_5, 255))

    # Bowl curve: M9,6 Q24,6 24,18 Q24,30 9,30
    curve1 = quadratic_bezier(
        (9 * scale, 6 * scale), (24 * scale, 6 * scale), (24 * scale, 18 * scale)
    )
    curve2 = quadratic_bezier(
        (24 * scale, 18 * scale), (24 * scale, 30 * scale), (9 * scale, 30 * scale)
    )
    all_points = curve1 + curve2[1:]  # avoid duplicate middle point

    # Draw as thick line segments
    for i in range(len(all_points) - 1):
        draw.line([all_points[i], all_points[i + 1]], fill=(*INK_5, 255), width=sw)

    return img


def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    pad = round(size * 0.12)
    inner = size - 2 * pad
    corner = round(inner * 0.22)

    # Background: flat ink-1
    bg = Image.new("RGBA", (inner, inner), (*INK_1, 255))
    mask = rounded_rect_mask((inner, inner), corner)
    bg.putalpha(mask)

    # Subtle border
    border_img = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    border_draw = ImageDraw.Draw(border_img)
    bw = max(1, size // 256)
    border_draw.rounded_rectangle(
        [0, 0, inner - 1, inner - 1],
        radius=corner, outline=(*INK_5, 80), width=bw
    )
    border_mask = rounded_rect_mask((inner, inner), corner)
    border_img.putalpha(border_mask)
    bg = Image.alpha_composite(bg, border_img)

    img.paste(bg, (pad, pad), bg)

    # -- Bar geometry --
    bar_heights = [0.40, 0.70, 1.0, 0.58, 0.32]
    num_bars = len(bar_heights)

    bar_area_x = pad + round(inner * 0.18)
    bar_area_w = inner - round(inner * 0.36)
    bar_area_bottom = pad + round(inner * 0.82)
    bar_area_top = pad + round(inner * 0.15)
    bar_max_h = bar_area_bottom - bar_area_top

    bar_w = round(bar_area_w / (num_bars * 2.0))
    bar_spacing = round(bar_area_w / num_bars)

    first_bx = bar_area_x + (bar_spacing - bar_w) // 2
    last_bx = bar_area_x + (num_bars - 1) * bar_spacing + (bar_spacing - bar_w) // 2 + bar_w
    bars_cx = (first_bx + last_bx) // 2

    # -- Render the "d" favicon behind bars --
    # Size it so the bowl spans the bar group height
    d_render_size = round(bar_max_h * 1.3)
    d_img = render_d_favicon(d_render_size)

    # Rotate -90° (counterclockwise) — bowl opens upward
    d_rotated = d_img.rotate(90, expand=True, resample=Image.BICUBIC)

    # Center on the bar group
    rx = bars_cx - d_rotated.width // 2
    ry = (bar_area_top + bar_area_bottom) // 2 - d_rotated.height // 2

    img.paste(d_rotated, (rx, ry), d_rotated)

    # -- EQ Bars (on top) --
    draw = ImageDraw.Draw(img)
    for i, h_frac in enumerate(bar_heights):
        bx = bar_area_x + i * bar_spacing + (bar_spacing - bar_w) // 2
        bar_h = round(bar_max_h * h_frac)
        by_top = bar_area_bottom - bar_h
        by_bot = bar_area_bottom

        split_y = by_top + round(bar_h * 0.4)

        draw.rectangle([bx, by_top, bx + bar_w - 1, split_y - 1], fill=(*ICE, 255))
        draw.rectangle([bx, split_y, bx + bar_w - 1, by_bot - 1], fill=(*EMBER, 255))

    # -- Glow layers --
    # 1) Broad radial glow behind bars (ambient light)
    ambient = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ambient_draw = ImageDraw.Draw(ambient)
    glow_cx = bars_cx
    glow_cy = (bar_area_top + bar_area_bottom) // 2
    glow_r = round(bar_max_h * 0.7)
    for r in range(glow_r, 0, -1):
        t = r / glow_r
        # Blend ember center to ice edge
        cr = int(EMBER[0] * (1 - t * 0.5) + ICE[0] * t * 0.5)
        cg = int(EMBER[1] * (1 - t * 0.5) + ICE[1] * t * 0.5)
        cb = int(EMBER[2] * (1 - t * 0.5) + ICE[2] * t * 0.5)
        alpha = int(40 * (1 - t) ** 1.5)
        if alpha > 0:
            ambient_draw.ellipse(
                [glow_cx - r, glow_cy - r, glow_cx + r, glow_cy + r],
                fill=(cr, cg, cb, alpha)
            )
    if size >= 64:
        ambient = ambient.filter(ImageFilter.GaussianBlur(radius=max(size // 40, 4)))
    img = Image.alpha_composite(img, ambient)

    # 2) Per-bar glow: ice on top, ember on bottom
    bar_glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bar_glow_draw = ImageDraw.Draw(bar_glow)
    for i, h_frac in enumerate(bar_heights):
        bx = bar_area_x + i * bar_spacing + (bar_spacing - bar_w) // 2
        bar_h = round(bar_max_h * h_frac)
        by_top = bar_area_bottom - bar_h
        by_bot = bar_area_bottom
        bcx = bx + bar_w // 2
        spread = round(bar_w * 2.5)

        # Ice glow above bar top
        ice_glow_h = round(bar_w * 3)
        for gy in range(ice_glow_h):
            alpha = int(55 * (1 - gy / ice_glow_h) ** 2)
            if alpha > 0:
                bar_glow_draw.line(
                    [(bcx - spread, by_top - gy), (bcx + spread, by_top - gy)],
                    fill=(*ICE, alpha)
                )

        # Ember glow below bar bottom
        ember_glow_h = round(bar_w * 3)
        for gy in range(ember_glow_h):
            alpha = int(65 * (1 - gy / ember_glow_h) ** 2)
            if alpha > 0:
                bar_glow_draw.line(
                    [(bcx - spread, by_bot + gy), (bcx + spread, by_bot + gy)],
                    fill=(*EMBER, alpha)
                )

        # Side glow along bar edges
        side_spread = round(bar_w * 1.5)
        for sx in range(side_spread):
            alpha = int(30 * (1 - sx / side_spread) ** 2)
            if alpha > 0:
                split_y = by_top + round(bar_h * 0.4)
                # Ice side glow (top portion)
                bar_glow_draw.line(
                    [(bx - sx, by_top), (bx - sx, split_y)], fill=(*ICE, alpha)
                )
                bar_glow_draw.line(
                    [(bx + bar_w + sx, by_top), (bx + bar_w + sx, split_y)], fill=(*ICE, alpha)
                )
                # Ember side glow (bottom portion)
                bar_glow_draw.line(
                    [(bx - sx, split_y), (bx - sx, by_bot)], fill=(*EMBER, alpha)
                )
                bar_glow_draw.line(
                    [(bx + bar_w + sx, split_y), (bx + bar_w + sx, by_bot)], fill=(*EMBER, alpha)
                )

    if size >= 64:
        bar_glow = bar_glow.filter(ImageFilter.GaussianBlur(radius=max(size // 60, 3)))
    img = Image.alpha_composite(img, bar_glow)

    return img


def main():
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    iconset_dir = os.path.join(os.path.dirname(__file__), "AppIcon.iconset")
    os.makedirs(iconset_dir, exist_ok=True)

    for s in sizes:
        icon = draw_icon(s)
        if s <= 512:
            icon.save(os.path.join(iconset_dir, f"icon_{s}x{s}.png"))
        if s >= 32:
            half = s // 2
            if half in [16, 32, 64, 128, 256, 512]:
                icon.save(os.path.join(iconset_dir, f"icon_{half}x{half}@2x.png"))

    print(f"Generated iconset at {iconset_dir}")

    icns_path = os.path.join(os.path.dirname(__file__), "Sources", "iQualize", "AppIcon.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path], check=True)
    print(f"Created {icns_path}")

    import shutil
    shutil.rmtree(iconset_dir)
    print("Cleaned up iconset directory")


if __name__ == "__main__":
    main()
