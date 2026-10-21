#!/usr/bin/env python3
"""Builds the app icon and the website favicon from Design/AppIcon.svg.

    python3 scripts/make-icon.py                 # writes App/Resources/AppIcon.icon and website/favicon.svg
    python3 scripts/make-icon.py --preview DIR   # also renders every appearance to DIR with Xcode's ictool

AppIcon.icon is an Icon Composer document: actool turns it into the Dock and Finder icon, and macOS
draws its light, dark, tinted and clear appearances from the layers. See the comment in the SVG for
what each attribute means.
"""
import copy
import json
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Design/AppIcon.svg"
ICON = ROOT / "App/Resources/AppIcon.icon"
FAVICON = ROOT / "website/favicon.svg"
ICTOOL = Path("/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")

SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)
NS = {"svg": SVG}


def color(hex_: str) -> str:
    """#RRGGBB → Icon Composer's "srgb:r,g,b,a"."""
    r, g, b = (int(hex_.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


def svg(defs: list, body: list) -> str:
    """A standalone 1024-pt SVG of `body`, with only the `defs` it refers to."""
    used = "".join(ET.tostring(e, encoding="unicode") for e in body)
    defs = [d for d in defs if f"url(#{d.get('id')})" in used]
    root = ET.Element(f"{{{SVG}}}svg", {"viewBox": "0 0 1024 1024", "width": "1024", "height": "1024"})
    if defs:
        ET.SubElement(root, f"{{{SVG}}}defs").extend(defs)
    root.extend(body)
    root = copy.deepcopy(root)
    for e in root.iter():
        e.text = e.text.strip() or None if e.text else None
        e.tail = None
        for key in [k for k in e.attrib if k.startswith("data-")]:
            del e.attrib[key]
    ET.indent(root)
    return ET.tostring(root, encoding="unicode") + "\n"


def main() -> None:
    tree = ET.parse(SOURCE).getroot()
    defs = tree.find("svg:defs", NS)
    fill = defs.find("svg:linearGradient[@id='fill']", NS)
    stops = [s.get("stop-color") for s in fill.findall("svg:stop", NS)]
    layers = tree.findall("svg:g[@id]", NS)

    # Icon Composer layers each get their own SVG; the background is the document's fill.
    shutil.rmtree(ICON, ignore_errors=True)
    (ICON / "Assets").mkdir(parents=True)
    groups = []
    for g in reversed(layers):  # icon.json lists the frontmost group first
        name = g.get("id")
        (ICON / "Assets" / f"{name}.svg").write_text(svg(list(defs), list(g)))
        layer = {"image-name": f"{name}.svg", "name": name}
        if g.get("data-glass") == "true":
            layer["glass"] = True
        if dark := g.get("data-dark"):
            layer["fill-specializations"] = [{"appearance": "dark", "value": {"solid": color(dark)}}]
        if tinted := g.get("data-tinted-opacity"):
            layer["opacity-specializations"] = [{"value": 1.0}, {"appearance": "tinted", "value": float(tinted)}]
        glass = "glass" in layer
        groups.append({
            "layers": [layer],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": glass, "value": 0.3 if glass else 0},
        })
    document = {
        "fill": {"linear-gradient": [color(c) for c in stops]},
        "fill-specializations": [
            {"appearance": "dark", "value": {"linear-gradient": [color(c) for c in fill.get("data-dark").split()]}},
        ],
        "groups": groups,
        "supported-platforms": {"squares": ["macOS"]},
    }
    (ICON / "icon.json").write_text(json.dumps(document, indent=2) + "\n")

    # The favicon is the light icon, flat: the rounded mask, and a hairline shadow under the lid
    # standing in for the depth macOS adds.
    mask = ET.fromstring(f'<clipPath xmlns="{SVG}" id="mask"><rect width="1024" height="1024" rx="230"/></clipPath>')
    body = ET.Element(f"{{{SVG}}}g", {"clip-path": "url(#mask)"})
    body.append(ET.Element(f"{{{SVG}}}rect", {"width": "1024", "height": "1024", "fill": "url(#fill)"}))
    for g in layers:
        if g.get("id") == "lid":
            lid = g.find("svg:rect", NS)
            body.append(ET.Element(f"{{{SVG}}}rect", {
                "y": lid.get("height"), "width": "1024", "height": "28", "fill": "#000", "opacity": ".12"}))
        body.extend(g)
    FAVICON.write_text(svg([*defs, mask], [body]))

    print(f"wrote {ICON.relative_to(ROOT)} and {FAVICON.relative_to(ROOT)}")

    if "--preview" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--preview") + 1])
        out.mkdir(parents=True, exist_ok=True)
        for rendition in ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]:
            for size in [16, 32, 128, 256, 512]:
                for scale in [1, 2]:
                    subprocess.run([
                        ICTOOL, ICON, "--export-image", "--output-file", out / f"{rendition}-{size}@{scale}x.png",
                        "--platform", "macOS", "--rendition", rendition,
                        "--width", str(size), "--height", str(size), "--scale", str(scale),
                    ], check=True, stdout=subprocess.DEVNULL)
        print(f"rendered previews into {out}")


if __name__ == "__main__":
    main()
