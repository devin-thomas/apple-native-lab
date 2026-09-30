#!/usr/bin/env python3
"""Generate the lab's app icon as an Icon Composer document (Apps/Icon/AppIcon.icon).

The mark is a gear (the system and its automation) around a laboratory flask (the lab), in one
electric-blue accent on a cool black field. Layers are vector SVG on a 1024-point canvas, so
Xcode renders every size, shape (squares and Watch circles), and appearance (default, dark,
clear, tinted) from one source. Rerun after changing the geometry:
    python3 script/make_app_icon.py
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ICON = ROOT / "Apps/Icon/AppIcon.icon"
ASSETS = ICON / "Assets"

CENTER = 512.0
BLUE = "#2F80FF"        # electric blue: the accent the house design guide reserves for action
BLUE_LIGHT = "#6FA8FF"  # the same hue, lighter, for the liquid
BACKGROUND = (0.024, 0.031, 0.051)  # cool black


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


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    gear = svg(
        f'  <path d="{gear_path()}" fill="{BLUE}" fill-rule="evenodd" '
        f'stroke="{BLUE}" stroke-width="18" stroke-linejoin="round"/>'
    )
    flask = svg(
        f'  <path d="{flask_outline_path()}" fill="none" stroke="{BLUE}" stroke-width="30" '
        'stroke-linecap="round" stroke-linejoin="round"/>'
    )
    liquid = svg(
        f'  <path d="{liquid_path()}" fill="{BLUE_LIGHT}"/>\n'
        f'  <circle cx="{CENTER + 20}" cy="{500}" r="12" fill="{BLUE_LIGHT}"/>\n'
        f'  <circle cx="{CENTER - 16}" cy="{470}" r="8" fill="{BLUE_LIGHT}"/>'
    )
    (ASSETS / "gear.svg").write_text(gear)
    (ASSETS / "flask.svg").write_text(flask)
    (ASSETS / "liquid.svg").write_text(liquid)

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


if __name__ == "__main__":
    main()
