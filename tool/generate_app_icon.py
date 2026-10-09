"""Generate FocusDesk branding with Pillow: python tool/generate_app_icon.py.

Foreground geometry fits Android's central 66/108 adaptive-icon safe circle.
All source images are deterministic, antialiased PNGs without external fonts.
"""

import argparse
from math import hypot
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image, ImageDraw


SIZE = 1024
SCALE = 2
PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = PROJECT_ROOT / "assets" / "images"
LIGHT_VIOLET = (139, 104, 208)
DARK_VIOLET = (77, 67, 169)
WHITE = (255, 255, 255, 255)


def gradient():
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = []
    for y in range(SIZE):
        for x in range(SIZE):
            blend = (x + y) / (2 * (SIZE - 1))
            pixels.append(tuple(round(a + (b - a) * blend)
                                for a, b in zip(LIGHT_VIOLET, DARK_VIOLET)) + (255,))
    image.putdata(pixels)
    return image


def glyph():
    image = Image.new("RGBA", (SIZE * SCALE, SIZE * SCALE))
    draw = ImageDraw.Draw(image)

    def box(values):
        return tuple(round(value * SCALE) for value in values)

    def rounded_line(points, width):
        scaled = [box(point) for point in points]
        draw.line(scaled, fill=WHITE, width=width * SCALE, joint="curve")
        radius = width * SCALE / 2
        for x, y in scaled:
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=WHITE)

    # Stopwatch stem and top button join a clean circular dial.
    draw.rounded_rectangle(box((490, 275, 534, 329)), radius=10 * SCALE, fill=WHITE)
    draw.rounded_rectangle(box((450, 239, 574, 277)), radius=14 * SCALE, fill=WHITE)
    draw.ellipse(box((290, 320, 734, 764)), outline=WHITE, width=44 * SCALE)
    # A check replaces clock hands: focus translates into a completed task.
    rounded_line([(408, 540), (486, 615), (625, 459)], 44)
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def save(image, name):
    path = OUTPUT / name
    image.save(path, optimize=True)
    print(f"{path.relative_to(OUTPUT.parent.parent)}: {image.width}x{image.height} {image.mode}")


def generate_icons():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    background = gradient()
    foreground = glyph()
    safe_radius = SIZE * 66 / 108 / 2
    furthest = max(hypot(x - SIZE / 2, y - SIZE / 2)
                   for y in range(SIZE) for x in range(SIZE)
                   if foreground.getpixel((x, y))[3] > 0)
    if furthest > safe_radius:
        raise ValueError("Foreground exceeds the Android adaptive-icon safe circle")
    mask = Image.new("L", (SIZE * SCALE, SIZE * SCALE))
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, SIZE * SCALE - 1, SIZE * SCALE - 1),
                                          radius=220 * SCALE, fill=255)
    mask = mask.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    launcher = background.copy()
    launcher.alpha_composite(foreground)
    launcher.putalpha(mask)
    save(launcher, "app_icon.png")
    save(background, "app_icon_background.png")
    save(foreground, "app_icon_foreground.png")
    # Legacy splash package expects a 4x raster: 416px renders at 104dp.
    save(launcher.resize((416, 416), Image.Resampling.LANCZOS), "splash_icon.png")
    # Android 12 icon with a background: 960px canvas, 640px safe circle.
    save(foreground.resize((960, 960), Image.Resampling.LANCZOS), "splash_android12.png")
    print(f"Adaptive glyph radius {furthest:.1f}px <= safe {safe_radius:.1f}px")


def fix_splash_themes():
    """Run after flutter_native_splash:create, which resets system-bar flags.

    Android's windowLightStatusBar/windowLightNavigationBar flags require
    windowDrawsSystemBarBackgrounds. Explicit day/night values keep native
    launch icons readable; NormalTheme covers the Flutter embedding handoff.
    """
    resources = PROJECT_ROOT / "android" / "app" / "src" / "main" / "res"
    for folder in ("values", "values-night", "values-v31", "values-night-v31"):
        path = resources / folder / "styles.xml"
        parser = ElementTree.XMLParser(target=ElementTree.TreeBuilder(insert_comments=True))
        tree = ElementTree.parse(path, parser=parser)
        root = tree.getroot()
        dark = "night" in folder
        background = "#15121D" if dark else "#FFFBFF"
        settings = {
            "android:windowDrawsSystemBarBackgrounds": "true",
            "android:windowLightStatusBar": "false" if dark else "true",
            "android:windowLightNavigationBar": "false" if dark else "true",
            "android:statusBarColor": background,
            "android:navigationBarColor": background,
        }
        for theme_name in ("LaunchTheme", "NormalTheme"):
            style = root.find(f"style[@name='{theme_name}']")
            if style is None:
                raise ValueError(f"Missing {theme_name} in {path}")
            for name, value in settings.items():
                item = style.find(f"item[@name='{name}']")
                if item is None:
                    item = ElementTree.SubElement(style, "item", {"name": name})
                item.text = value
        ElementTree.indent(tree, space="    ")
        tree.write(path, encoding="utf-8", xml_declaration=True)
        print(f"{path.relative_to(PROJECT_ROOT)}: {'dark' if dark else 'light'} native system bars")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fix-splash-themes", action="store_true",
                        help="Apply native system-bar contrast after the Dart splash generator")
    if parser.parse_args().fix_splash_themes:
        fix_splash_themes()
    else:
        generate_icons()


if __name__ == "__main__":
    main()
