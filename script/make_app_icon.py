#!/usr/bin/env python3
"""Generate the lab's app icon from one geometry, for every platform.

The mark is a gear (the system and its automation) around a laboratory flask (the lab), in one
electric-blue accent on a cool black field. It is written twice from the same paths:

- Apps/Icon/AppIcon.icon, an Icon Composer document for the Mac, iPhone, and Watch hosts. Layers
  are vector SVG on a 1024-point canvas, so Xcode renders every size, shape (squares and Watch
  circles), and appearance (default, dark, clear, tinted) from one source.
- Apps/TV/Assets.xcassets/AppIcon.brandassets, the Apple TV host's layered icon and Top Shelf
  images. Icon Composer documents do not compile for tvOS (actool looks for an "App Icon & Top
  Shelf Image" brand assets collection instead), so the same paths are placed on the 5:3 icon and
  the wide Top Shelf canvases as SVG, which the asset catalog keeps as vectors. The icon has three
  layers for the focus parallax: the field at the back, the gear, and the flask in front.

Rerun after changing the geometry, and commit both outputs:
    python3 script/make_app_icon.py
"""
import json
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Apps/Icon/AppIcon.icon"
ASSETS = ICON / "Assets"
TV_CATALOG = ROOT / "Apps/TV/Assets.xcassets"
TV_BRAND = TV_CATALOG / "AppIcon.brandassets"

CENTER = 512.0
BLUE = "#2F80FF"        # electric blue: the accent the house design guide reserves for action
BLUE_LIGHT = "#6FA8FF"  # the same hue, lighter, for the liquid
BACKGROUND = (0.024, 0.031, 0.051)  # cool black

# tvOS canvases in points (width, height), and how much of the 1024-point artwork's height each
# shows. A taller view leaves the mark smaller, inside the area the focus effect never crops.
TV_ICON = (400, 240)            # the Home Screen icon, rendered at 1x and 2x
TV_ICON_STORE = (1280, 768)     # the App Store icon
TV_TOP_SHELF = (1920, 720)      # the Top Shelf image
TV_TOP_SHELF_WIDE = (2320, 720)  # the wide Top Shelf image
TV_ICON_VIEW_HEIGHT = 1160.0
TV_TOP_SHELF_VIEW_HEIGHT = 1400.0
CATALOG_INFO = {"author": "xcode", "version": 1}


def point(angle_deg: float, radius: float) -> tuple[float, float]:
    a = math.radians(angle_deg)
    return CENTER + radius * math.cos(a), CENTER + radius * math.sin(a)


def fmt(p: tuple[float, float]) -> str:
    return f"{p[0]:.2f} {p[1]:.2f}"


def gear_path(teeth: int = 8, tip: float = 352.0, root: float = 296.0, hole: float = 234.0) -> str:
    """A ring with trapezoid teeth; one tooth points straight up."""
    pitch = 360.0 / teeth
    tip_half, root_half = pitch * 0.19, pitch * 0.30
    parts = []
    for i in range(teeth):
        a = -90.0 + i * pitch
        root_start, tip_start = point(a - root_half, root), point(a - tip_half, tip)
        tip_end, root_end = point(a + tip_half, tip), point(a + root_half, root)
        next_root = point(a + pitch - root_half, root)
        parts.append(("M " if i == 0 else "L ") + fmt(root_start))
        parts.append("L " + fmt(tip_start))
        parts.append(f"A {tip} {tip} 0 0 1 " + fmt(tip_end))
        parts.append("L " + fmt(root_end))
        parts.append(f"A {root} {root} 0 0 1 " + fmt(next_root))
    parts.append("Z")
    # The hole, drawn as two arcs; even-odd filling cuts it out of the ring.
    top, bottom = (CENTER, CENTER - hole), (CENTER, CENTER + hole)
    parts.append(f"M {fmt(top)} A {hole} {hole} 0 1 0 {fmt(bottom)} A {hole} {hole} 0 1 0 {fmt(top)} Z")
    return " ".join(parts)


def flask_outline_path() -> str:
    """An Erlenmeyer flask: a lip, a narrow neck, sloped shoulders, and a rounded base."""
    neck, lip, base = 40.0, 64.0, 138.0
    top, neck_bottom, bottom, corner = 352.0, 444.0, 632.0, 32.0
    left, right = CENTER - base, CENTER + base
    return " ".join([
        f"M {CENTER - lip} {top}",
        f"L {CENTER + lip} {top}",
        f"M {CENTER - neck} {top}",
        f"L {CENTER - neck} {neck_bottom}",
        f"L {left + corner * 0.35} {bottom - corner}",
        f"Q {left} {bottom} {left + corner} {bottom}",
        f"L {right - corner} {bottom}",
        f"Q {right} {bottom} {right - corner * 0.35} {bottom - corner}",
        f"L {CENTER + neck} {neck_bottom}",
        f"L {CENTER + neck} {top}",
    ])


def liquid_path() -> str:
    """The liquid in the flask's lower half, with a gentle wave for a surface."""
    neck, base = 40.0, 138.0
    neck_bottom, bottom, corner = 444.0, 632.0, 32.0
    surface = 540.0
    inset = 30.0  # stays inside the outline's stroke

    def half_width(y: float) -> float:
        t = (y - neck_bottom) / (bottom - neck_bottom)
        return neck + (base - neck) * t

    w_surface = half_width(surface) - inset
    left, right = CENTER - (base - inset), CENTER + (base - inset)
    floor = bottom - inset * 0.9
    return " ".join([
        f"M {CENTER - w_surface:.2f} {surface}",
        f"C {CENTER - w_surface * 0.4:.2f} {surface - 18} {CENTER - w_surface * 0.1:.2f} {surface + 16} {CENTER + w_surface * 0.25:.2f} {surface}",
        f"S {CENTER + w_surface * 0.8:.2f} {surface - 10} {CENTER + w_surface:.2f} {surface}",
        f"L {right - corner * 0.4:.2f} {floor - corner * 0.6:.2f}",
        f"Q {right:.2f} {floor:.2f} {right - corner:.2f} {floor:.2f}",
        f"L {left + corner:.2f} {floor:.2f}",
        f"Q {left:.2f} {floor:.2f} {left + corner * 0.4:.2f} {floor - corner * 0.6:.2f}",
        "Z",
    ])


def svg(body: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n'
        f"{body}\n</svg>\n"
    )


# The mark's elements, shared by every output. Each is indented for an SVG body.

def gear_element() -> str:
    return (
        f'  <path d="{gear_path()}" fill="{BLUE}" fill-rule="evenodd" '
        f'stroke="{BLUE}" stroke-width="18" stroke-linejoin="round"/>'
    )


def flask_element() -> str:
    return (
        f'  <path d="{flask_outline_path()}" fill="none" stroke="{BLUE}" stroke-width="30" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
    )


def liquid_elements() -> str:
    return (
        f'  <path d="{liquid_path()}" fill="{BLUE_LIGHT}"/>\n'
        f'  <circle cx="{CENTER + 20}" cy="{500}" r="12" fill="{BLUE_LIGHT}"/>\n'
        f'  <circle cx="{CENTER - 16}" cy="{470}" r="8" fill="{BLUE_LIGHT}"/>'
    )


def background_hex() -> str:
    return "#" + "".join(f"{round(channel * 255):02X}" for channel in BACKGROUND)


# MARK: - tvOS

def tv_svg(size: tuple[int, int], view_height: float, body: str) -> str:
    """The 1024-point artwork centered on a canvas of `size` points, showing `view_height` of it."""
    width, height = size
    view_width = view_height * width / height
    x, y = CENTER - view_width / 2, CENTER - view_height / 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="{x:.2f} {y:.2f} {view_width:.2f} {view_height:.2f}">\n{body}\n</svg>\n'
    )


def tv_field(size: tuple[int, int], view_height: float) -> str:
    """The opaque cool-black field, filling the whole canvas."""
    width, height = size
    view_width = view_height * width / height
    x, y = CENTER - view_width / 2, CENTER - view_height / 2
    return f'  <rect x="{x:.2f}" y="{y:.2f}" width="{view_width:.2f}" height="{view_height:.2f}" fill="{background_hex()}"/>'


def write_json(folder: Path, document: dict) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "Contents.json").write_text(json.dumps(document, indent=2) + "\n")


def write_vector_imageset(folder: Path, filename: str, contents: str) -> None:
    write_json(folder, {
        "images": [{"filename": filename, "idiom": "tv"}],
        "info": CATALOG_INFO,
        "properties": {"preserves-vector-representation": True},
    })
    (folder / filename).write_text(contents)


def write_tv_icon_stack(folder: Path, size: tuple[int, int]) -> None:
    """A layered tvOS icon: back to front, the field, the gear, and the flask with its liquid."""
    layers = [
        ("Front", "flask", flask_element() + "\n" + liquid_elements()),
        ("Middle", "gear", gear_element()),
        ("Back", "field", tv_field(size, TV_ICON_VIEW_HEIGHT)),
    ]
    write_json(folder, {"info": CATALOG_INFO, "layers": [{"filename": f"{name}.imagestacklayer"} for name, _, _ in layers]})
    for name, image, body in layers:
        layer = folder / f"{name}.imagestacklayer"
        write_json(layer, {"info": CATALOG_INFO})
        write_vector_imageset(layer / "Content.imageset", f"{image}.svg", tv_svg(size, TV_ICON_VIEW_HEIGHT, body))


def write_tv_brand_assets() -> None:
    """Apps/TV/Assets.xcassets: the App Icon and Top Shelf Image brand assets, named AppIcon."""
    shutil.rmtree(TV_CATALOG, ignore_errors=True)
    write_json(TV_CATALOG, {"info": CATALOG_INFO})
    write_json(TV_BRAND, {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon",
             "size": "{}x{}".format(*TV_ICON_STORE)},
            {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon",
             "size": "{}x{}".format(*TV_ICON)},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide",
             "size": "{}x{}".format(*TV_TOP_SHELF_WIDE)},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image",
             "size": "{}x{}".format(*TV_TOP_SHELF)},
        ],
        "info": CATALOG_INFO,
    })
    write_tv_icon_stack(TV_BRAND / "App Icon.imagestack", TV_ICON)
    write_tv_icon_stack(TV_BRAND / "App Icon - App Store.imagestack", TV_ICON_STORE)
    mark = gear_element() + "\n" + flask_element() + "\n" + liquid_elements()
    for folder, size in (("Top Shelf Image.imageset", TV_TOP_SHELF), ("Top Shelf Image Wide.imageset", TV_TOP_SHELF_WIDE)):
        body = tv_field(size, TV_TOP_SHELF_VIEW_HEIGHT) + "\n" + mark
        write_vector_imageset(TV_BRAND / folder, "top-shelf.svg", tv_svg(size, TV_TOP_SHELF_VIEW_HEIGHT, body))


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "gear.svg").write_text(svg(gear_element()))
    (ASSETS / "flask.svg").write_text(svg(flask_element()))
    (ASSETS / "liquid.svg").write_text(svg(liquid_elements()))

    r, g, b = BACKGROUND
    document = {
        "fill": {"solid": f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"},
        "groups": [
            {
                "layers": [
                    {"glass": True, "image-name": "liquid.svg", "name": "liquid"},
                    {"glass": True, "image-name": "flask.svg", "name": "flask"},
                ],
                "shadow": {"kind": "layer-color", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.35},
            },
            {
                "layers": [{"glass": True, "image-name": "gear.svg", "name": "gear"}],
                "shadow": {"kind": "layer-color", "opacity": 0.5},
                "translucency": {"enabled": True, "value": 0.35},
            },
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2) + "\n")
    print(f"wrote {ICON.relative_to(ROOT)}")
    write_tv_brand_assets()
    print(f"wrote {TV_BRAND.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
