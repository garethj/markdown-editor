#!/usr/bin/env python3
"""Generate macOS app icon for MarkdownEditor."""

import json
import math
from PIL import Image, ImageDraw

OUTPUT_DIR = "MarkdownEditor/Assets.xcassets/AppIcon.appiconset"

# All required sizes: (pixel_size, point_size, scale)
ICON_SIZES = [
    (16,   "16x16",  "1x"),
    (32,   "16x16",  "2x"),
    (32,   "32x32",  "1x"),
    (64,   "32x32",  "2x"),
    (128,  "128x128", "1x"),
    (256,  "128x128", "2x"),
    (256,  "256x256", "1x"),
    (512,  "256x256", "2x"),
    (512,  "512x512", "1x"),
    (1024, "512x512", "2x"),
]


def lerp_color(c1, c2, t):
    """Linearly interpolate between two RGB colors."""
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def draw_rounded_rect(draw, bbox, radius, fill):
    """Draw a rounded rectangle."""
    x0, y0, x1, y1 = bbox
    # Clamp radius
    r = min(radius, (x1 - x0) // 2, (y1 - y0) // 2)

    # Four corners as circles
    draw.ellipse([x0, y0, x0 + 2 * r, y0 + 2 * r], fill=fill)
    draw.ellipse([x1 - 2 * r, y0, x1, y0 + 2 * r], fill=fill)
    draw.ellipse([x0, y1 - 2 * r, x0 + 2 * r, y1], fill=fill)
    draw.ellipse([x1 - 2 * r, y1 - 2 * r, x1, y1], fill=fill)

    # Rectangles to fill the rest
    draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    draw.rectangle([x0, y0 + r, x1, y1 - r], fill=fill)


def create_icon(size):
    """Create the icon at the given pixel size."""
    # Work at 4x resolution for antialiasing, then downscale
    render_size = max(size * 4, 512)
    img = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    s = render_size  # shorthand
    corner_radius = int(s * 0.22)  # macOS-style rounded corners

    # --- Background gradient (top-left purple to bottom-right blue) ---
    # We'll draw the gradient line by line, then mask with rounded rect
    gradient = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    grad_draw = ImageDraw.Draw(gradient)

    top_color = (130, 80, 220)      # purple
    bottom_color = (50, 130, 240)   # blue

    for y in range(s):
        t = y / (s - 1)
        color = lerp_color(top_color, bottom_color, t)
        grad_draw.line([(0, y), (s - 1, y)], fill=(*color, 255))

    # Create rounded rect mask
    mask = Image.new("L", (s, s), 0)
    mask_draw = ImageDraw.Draw(mask)
    draw_rounded_rect(mask_draw, [0, 0, s - 1, s - 1], corner_radius, 255)

    # Apply mask to gradient
    gradient.putalpha(mask)
    img = gradient

    draw = ImageDraw.Draw(img)

    # --- Subtle inner shadow / highlight at top ---
    highlight_color = (255, 255, 255, 30)
    for i in range(int(s * 0.03)):
        y = int(s * 0.02) + i
        alpha = int(30 * (1 - i / (s * 0.03)))
        x_start = corner_radius if y < corner_radius else int(s * 0.02)
        x_end = s - x_start
        draw.line([(x_start, y), (x_end, y)], fill=(255, 255, 255, alpha))

    # --- Draw the Markdown down-arrow symbol ---
    # The classic Markdown logo: "M" with a down arrow
    # We'll draw a stylized M and a small down-arrow beneath

    white = (255, 255, 255, 240)
    shadow = (0, 0, 0, 50)

    # Compute M dimensions
    margin = s * 0.18
    m_top = s * 0.20
    m_bottom = s * 0.60
    m_height = m_bottom - m_top
    stroke_w = s * 0.07

    left = margin
    right = s - margin
    m_width = right - left

    # Draw the "M" as a series of thick lines
    # Left vertical stroke
    _draw_thick_line(draw, left, m_top, left, m_bottom, stroke_w, white)
    # Left diagonal going down to center
    cx = s * 0.5
    _draw_thick_line(draw, left, m_top, cx, m_top + m_height * 0.6, stroke_w, white)
    # Right diagonal going down to center
    _draw_thick_line(draw, right, m_top, cx, m_top + m_height * 0.6, stroke_w, white)
    # Right vertical stroke
    _draw_thick_line(draw, right, m_top, right, m_bottom, stroke_w, white)

    # --- Down arrow below the M (Markdown symbol) ---
    arrow_top = s * 0.66
    arrow_bottom = s * 0.82
    arrow_width = s * 0.22
    arrow_cx = s * 0.5

    # Vertical shaft of arrow
    _draw_thick_line(draw, arrow_cx, arrow_top, arrow_cx, arrow_bottom, stroke_w * 0.8, white)

    # Arrow head (two diagonal lines)
    head_size = s * 0.10
    _draw_thick_line(draw, arrow_cx - head_size, arrow_bottom - head_size,
                     arrow_cx, arrow_bottom, stroke_w * 0.8, white)
    _draw_thick_line(draw, arrow_cx + head_size, arrow_bottom - head_size,
                     arrow_cx, arrow_bottom, stroke_w * 0.8, white)

    # Downscale with high-quality resampling
    if render_size != size:
        img = img.resize((size, size), Image.LANCZOS)

    return img


def _draw_thick_line(draw, x1, y1, x2, y2, width, fill):
    """Draw a line with a given thickness using a polygon."""
    # Calculate perpendicular offset
    dx = x2 - x1
    dy = y2 - y1
    length = math.sqrt(dx * dx + dy * dy)
    if length == 0:
        return

    # Unit perpendicular vector
    px = -dy / length * width / 2
    py = dx / length * width / 2

    # Draw as polygon for clean thick lines
    points = [
        (x1 + px, y1 + py),
        (x1 - px, y1 - py),
        (x2 - px, y2 - py),
        (x2 + px, y2 + py),
    ]
    draw.polygon(points, fill=fill)

    # Round caps
    r = width / 2
    draw.ellipse([x1 - r, y1 - r, x1 + r, y1 + r], fill=fill)
    draw.ellipse([x2 - r, y2 - r, x2 + r, y2 + r], fill=fill)


def get_filename(pixel_size, point_size, scale):
    """Generate a filename for the icon."""
    return f"app_icon_{pixel_size}.png"


def main():
    images_json = []

    for pixel_size, point_size, scale in ICON_SIZES:
        filename = get_filename(pixel_size, point_size, scale)
        # Handle duplicate pixel sizes (32x32 and 256x256 appear twice)
        if scale == "2x" and any(
            ps == pixel_size and sc == "1x"
            for ps, _, sc in ICON_SIZES
        ):
            # Use a different filename for the 2x variant
            filename = f"app_icon_{pixel_size}_2x.png"

        icon = create_icon(pixel_size)
        filepath = f"{OUTPUT_DIR}/{filename}"
        icon.save(filepath, "PNG")
        print(f"Generated {filepath} ({pixel_size}x{pixel_size})")

        images_json.append({
            "filename": filename,
            "idiom": "mac",
            "scale": scale,
            "size": point_size,
        })

    # Write Contents.json
    contents = {
        "images": images_json,
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }

    contents_path = f"{OUTPUT_DIR}/Contents.json"
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"\nUpdated {contents_path}")


if __name__ == "__main__":
    main()
