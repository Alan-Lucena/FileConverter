"""Generate marketing mockup of the File Converter context menu in Finder.

Produces assets/menu.png at retina-scale resolution, showing the right-click
menu with the "Convert File" submenu open. Uses no real screenshots; the
layout is approximate and styled to evoke macOS dark mode.
"""

from __future__ import annotations
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

SCALE = 2
W, H = 1280 * SCALE, 880 * SCALE

# Colors (macOS dark mode-ish)
BG_GRAD_TOP = (28, 28, 32)
BG_GRAD_BOT = (10, 10, 14)
WIN_BG = (40, 40, 44, 245)
SIDEBAR_BG = (32, 32, 36)
DIVIDER = (60, 60, 64)
TEXT = (240, 240, 240)
TEXT_DIM = (170, 170, 175)
TEXT_FAINT = (130, 130, 135)
ROW_SELECTED = (10, 132, 255)
MENU_BG = (50, 50, 54, 250)
MENU_BORDER = (90, 90, 95, 200)
MENU_HIGHLIGHT = (10, 132, 255)
MENU_SEPARATOR = (78, 78, 82)
SHADOW = (0, 0, 0, 90)


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    """Best-effort SF Pro lookup with safe fallbacks."""
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/SFNSDisplay.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size * SCALE)
            except OSError:
                continue
    return ImageFont.load_default()


def gradient_bg() -> Image.Image:
    img = Image.new("RGB", (W, H), BG_GRAD_TOP)
    px = img.load()
    for y in range(H):
        t = y / H
        r = int(BG_GRAD_TOP[0] * (1 - t) + BG_GRAD_BOT[0] * t)
        g = int(BG_GRAD_TOP[1] * (1 - t) + BG_GRAD_BOT[1] * t)
        b = int(BG_GRAD_TOP[2] * (1 - t) + BG_GRAD_BOT[2] * t)
        for x in range(W):
            px[x, y] = (r, g, b)
    return img


def rounded_rect(draw, box, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius * SCALE, fill=fill, outline=outline, width=width * SCALE)


def draw_drop_shadow(base: Image.Image, box: tuple[int, int, int, int], radius: int, blur: int):
    """Soft shadow for a rounded rect."""
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle(box, radius=radius * SCALE, fill=SHADOW)
    layer = layer.filter(ImageFilter.GaussianBlur(radius=blur * SCALE))
    base.alpha_composite(layer)


def draw_finder_window(canvas: Image.Image):
    win = (50 * SCALE, 60 * SCALE, 600 * SCALE, 750 * SCALE)
    draw_drop_shadow(canvas, win, radius=14, blur=22)
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle(win, radius=14 * SCALE, fill=WIN_BG)
    canvas.alpha_composite(overlay)

    d = ImageDraw.Draw(canvas)

    # Traffic lights
    cx = win[0] + 22 * SCALE
    cy = win[1] + 22 * SCALE
    for i, color in enumerate([(255, 95, 87), (255, 189, 46), (39, 201, 63)]):
        d.ellipse(
            (cx + i * 22 * SCALE, cy, cx + i * 22 * SCALE + 14 * SCALE, cy + 14 * SCALE),
            fill=color,
        )

    # Sidebar
    sidebar = (win[0], win[1] + 44 * SCALE, win[0] + 180 * SCALE, win[3])
    d.rounded_rectangle(sidebar, radius=0, fill=SIDEBAR_BG)
    d.line([(sidebar[2], sidebar[1]), (sidebar[2], sidebar[3])], fill=DIVIDER, width=SCALE)

    f_section = font(11, True)
    f_item = font(13)

    sx = sidebar[0] + 18 * SCALE
    sy = sidebar[1] + 18 * SCALE
    d.text((sx, sy), "Favorites", font=f_section, fill=TEXT_FAINT)
    sy += 26 * SCALE

    sidebar_items = [
        ("AirDrop", (90, 130, 200), False),
        ("Recents", (140, 100, 200), False),
        ("Applications", (60, 160, 90), False),
        ("Desktop", (90, 130, 200), False),
        ("Documents", (90, 130, 200), True),
        ("Downloads", (60, 160, 90), False),
        ("Pictures", (140, 100, 200), False),
    ]
    for label, icon_color, sel in sidebar_items:
        if sel:
            d.rounded_rectangle(
                (sx - 8 * SCALE, sy - 4 * SCALE, sidebar[2] - 12 * SCALE, sy + 22 * SCALE),
                radius=6 * SCALE,
                fill=(70, 70, 75),
            )
        d.rounded_rectangle((sx, sy + 2 * SCALE, sx + 14 * SCALE, sy + 16 * SCALE), radius=3 * SCALE, fill=icon_color)
        d.text((sx + 22 * SCALE, sy), label, font=f_item, fill=TEXT)
        sy += 30 * SCALE

    # Title
    f_title = font(15, True)
    d.text((sidebar[2] + 24 * SCALE, win[1] + 14 * SCALE), "Documents", font=f_title, fill=TEXT)

    # File list area
    list_x = sidebar[2] + 1
    list_y = win[1] + 70 * SCALE
    list_right = win[2] - 1

    f_file = font(13)
    files = [
        ("Photo.png", True),
        ("Report.pdf", False),
        ("Notes.txt", False),
        ("Photo (1).png", False),
        ("scan.jpg", False),
        ("invoice-2026.pdf", False),
        ("avatar.heic", False),
        ("Logo.png", False),
        ("Screenshot.png", False),
    ]
    for name, sel in files:
        row_box = (list_x + 12 * SCALE, list_y, list_right - 12 * SCALE, list_y + 32 * SCALE)
        if sel:
            d.rounded_rectangle(row_box, radius=6 * SCALE, fill=ROW_SELECTED)
            d.rectangle((row_box[0] + 2 * SCALE, row_box[1] + 2 * SCALE, row_box[0] + 2 * SCALE + 1, row_box[3] - 2 * SCALE), fill=(255, 255, 255))
        # icon placeholder
        ic = (list_x + 24 * SCALE, list_y + 6 * SCALE, list_x + 24 * SCALE + 20 * SCALE, list_y + 6 * SCALE + 20 * SCALE)
        if name.endswith(".pdf"):
            d.rounded_rectangle(ic, radius=3 * SCALE, fill=(220, 70, 70))
        elif name.endswith(".png"):
            d.rounded_rectangle(ic, radius=3 * SCALE, fill=(70, 130, 220))
        elif name.endswith(".jpg") or name.endswith(".jpeg"):
            d.rounded_rectangle(ic, radius=3 * SCALE, fill=(230, 160, 60))
        elif name.endswith(".heic"):
            d.rounded_rectangle(ic, radius=3 * SCALE, fill=(120, 90, 200))
        else:
            d.rounded_rectangle(ic, radius=3 * SCALE, fill=(100, 100, 105))

        d.text((list_x + 56 * SCALE, list_y + 8 * SCALE), name, font=f_file, fill=TEXT if sel else TEXT)
        list_y += 36 * SCALE


def draw_context_menu(canvas: Image.Image):
    menu_x = 540 * SCALE
    menu_y = 110 * SCALE
    menu_w = 320 * SCALE
    menu_h = 660 * SCALE
    menu_box = (menu_x, menu_y, menu_x + menu_w, menu_y + menu_h)
    draw_drop_shadow(canvas, menu_box, radius=10, blur=28)

    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle(menu_box, radius=10 * SCALE, fill=MENU_BG)
    od.rounded_rectangle(menu_box, radius=10 * SCALE, outline=MENU_BORDER, width=SCALE)
    canvas.alpha_composite(overlay)

    d = ImageDraw.Draw(canvas)
    f = font(13)

    items = [
        ("Open", None),
        ("Open With", "›"),
        ("__sep__", None),
        ("Move to Trash", None),
        ("__sep__", None),
        ("Get Info", None),
        ("Rename", None),
        ('Compress "Photo.png"', None),
        ("Duplicate", None),
        ("Make Alias", None),
        ("Quick Look", None),
        ("__sep__", None),
        ("Copy", None),
        ("Share…", None),
        ("__sep__", None),
        ("__tags__", None),
        ("Tags…", None),
        ("__sep__", None),
        ("Show Preview Options", None),
        ("Quick Actions", "›"),
        ("__highlight__", "Convert File"),
        ("Set as Desktop Picture", None),
    ]
    convert_index = next(i for i, it in enumerate(items) if it[0] == "__highlight__")

    pad_x = 16 * SCALE
    cy = menu_y + 12 * SCALE
    line_h = 28 * SCALE
    sep_h = 10 * SCALE
    tag_h = 32 * SCALE
    convert_y_top = None

    for label, accessory in items:
        if label == "__sep__":
            d.line(
                [(menu_x + pad_x, cy + 4 * SCALE), (menu_x + menu_w - pad_x, cy + 4 * SCALE)],
                fill=MENU_SEPARATOR,
                width=SCALE,
            )
            cy += sep_h
        elif label == "__tags__":
            colors = [
                (255, 95, 87), (255, 159, 64), (255, 204, 0),
                (52, 199, 89), (10, 132, 255), (191, 90, 242), (174, 174, 178),
            ]
            tx = menu_x + pad_x
            for col in colors:
                d.ellipse((tx, cy + 6 * SCALE, tx + 18 * SCALE, cy + 24 * SCALE), fill=col)
                tx += 26 * SCALE
            cy += tag_h
        elif label == "__highlight__":
            convert_y_top = cy
            d.rounded_rectangle(
                (menu_x + 6 * SCALE, cy, menu_x + menu_w - 6 * SCALE, cy + line_h),
                radius=6 * SCALE,
                fill=MENU_HIGHLIGHT,
            )
            d.text((menu_x + pad_x, cy + 5 * SCALE), str(accessory), font=f, fill=(255, 255, 255))
            d.text((menu_x + menu_w - pad_x - 14 * SCALE, cy + 5 * SCALE), "›", font=f, fill=(255, 255, 255))
            cy += line_h
        else:
            d.text((menu_x + pad_x, cy + 5 * SCALE), label, font=f, fill=TEXT)
            if accessory:
                d.text((menu_x + menu_w - pad_x - 14 * SCALE, cy + 5 * SCALE), accessory, font=f, fill=TEXT_DIM)
            cy += line_h

    return menu_x, menu_y, menu_w, menu_h, convert_y_top


def draw_submenu(canvas: Image.Image, anchor):
    menu_x, menu_y, menu_w, menu_h, convert_y = anchor
    sub_x = menu_x + menu_w - 4 * SCALE
    sub_w = 130 * SCALE
    formats = ["PNG", "JPG", "PDF", "TIFF", "BMP", "GIF", "HEIC"]
    line_h = 30 * SCALE
    sub_h = line_h * len(formats) + 16 * SCALE
    sub_y = (convert_y or menu_y) - 6 * SCALE
    if sub_y + sub_h > H - 30 * SCALE:
        sub_y = H - 30 * SCALE - sub_h
    sub_box = (sub_x, sub_y, sub_x + sub_w, sub_y + sub_h)
    draw_drop_shadow(canvas, sub_box, radius=10, blur=24)

    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    od.rounded_rectangle(sub_box, radius=10 * SCALE, fill=MENU_BG)
    od.rounded_rectangle(sub_box, radius=10 * SCALE, outline=MENU_BORDER, width=SCALE)
    canvas.alpha_composite(overlay)

    d = ImageDraw.Draw(canvas)
    f = font(14, True)
    cy = sub_y + 8 * SCALE
    for fmt in formats:
        d.text((sub_x + 22 * SCALE, cy + 6 * SCALE), fmt, font=f, fill=TEXT)
        cy += line_h


def draw_caption(canvas: Image.Image):
    d = ImageDraw.Draw(canvas)
    f_big = font(20, True)
    f_small = font(12)
    cap_x = 80 * SCALE
    cap_y = 800 * SCALE
    d.text((cap_x, cap_y), "Right-click. Pick a format.", font=f_big, fill=TEXT)
    d.text((cap_x, cap_y + 30 * SCALE), "Files are saved next to the original.", font=f_small, fill=TEXT_DIM)


def main():
    canvas = gradient_bg().convert("RGBA")
    draw_finder_window(canvas)
    anchor = draw_context_menu(canvas)
    draw_submenu(canvas, anchor)
    draw_caption(canvas)

    out_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(out_dir, "menu.png")
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print("wrote", out_path)


if __name__ == "__main__":
    main()
