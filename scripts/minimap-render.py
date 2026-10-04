#!/usr/bin/env python3
"""Draw tiny font glyphs and encode the canvas with the Sixel protocol.

Worker input/output is newline-delimited JSON. Only Neovim sends graphics to the
terminal, after checking that the response and destination are still current.
"""
from __future__ import annotations

import argparse
from functools import lru_cache
import json
import math
import os
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

_glyph_key, _glyph_image = None, None


@lru_cache(maxsize=2048)
def glyph_sprite(path, size, char, advance, color):
    font = cjk_font(size) if any(0x2e80 <= ord(c) <= 0x9fff for c in char) else None
    font = font or font_for(path, size)
    left, top, right, bottom = font.getbbox(char, anchor="ls")
    mask = Image.new("RGBA", (max(1, right - left), max(1, bottom - top)))
    ImageDraw.Draw(mask).text((-left, -top), char, font=font, fill=rgb(color), anchor="ls")
    scale = advance / max(1, font_for(path, size).getlength('M'))
    mask = mask.resize((max(1, round(mask.width * scale)), mask.height), Image.Resampling.BILINEAR)
    return mask, round(left * scale), top


def rgb(value):
    return value >> 16 & 255, value >> 8 & 255, value & 255


@lru_cache(maxsize=12)
def font_for(path, size):
    target = Path(path) if path else Path(__file__).resolve().parents[1] / "fonts/ForgeMonoGeometry6NF-Regular.ttf"
    return ImageFont.truetype(str(target), size, layout_engine=ImageFont.Layout.BASIC)


@lru_cache(maxsize=8)
def cjk_font(size):
    candidates = [Path(os.environ.get("WINDIR", "/mnt/c/Windows")) / "Fonts/msyh.ttc"]
    candidates.extend(Path("/usr/share/fonts").glob("**/*CJK*.ttc"))
    for path in candidates:
        if path.is_file():
            return ImageFont.truetype(str(path), size, layout_engine=ImageFont.Layout.BASIC)
    return None


def glyphs(model, width, height, line_height, padding, font_size, font, advance):
    global _glyph_key, _glyph_image
    key = (width, height, line_height, padding, font_size, advance, model.get("font", ""), model.get("characters", []))
    if _glyph_key == key:
        return _glyph_image
    layer = Image.new("RGBA", (width, height))
    draw = ImageDraw.Draw(layer)
    # A real monospace font, a shared baseline and syntax colour per glyph.
    for index, cells in enumerate(model.get("characters", [])):
        baseline = round((index + .82) * line_height)
        for cell in cells:
            x = padding + cell["column"] * advance
            if x >= width - padding:
                break
            sprite, left, top = glyph_sprite(model.get('font', ''), font_size, cell['char'], advance, cell['color'])
            layer.alpha_composite(sprite, (round(x) + left, baseline + top))
    # One in-memory source slice only; cursor/selection changes reuse its ink.
    _glyph_key, _glyph_image = key, layer
    return layer


def render(model, shadows=True):
    width, height = int(model["pixel_width"]), int(model["pixel_height"])
    if not 1 <= width <= 2048 or not 1 <= height <= 4096:
        raise ValueError("Minimap canvas exceeds its bounds")
    image = Image.new("RGB", (width, height), rgb(model["background"]))
    draw = ImageDraw.Draw(image)
    resolution = model["resolution"]
    line_height = model["cell_height"] / resolution
    origin = model["offset"] * resolution
    if model.get("large"):
        line_height, origin = height / max(1, model["count"]), 0
    padding = max(2, round(model["cell_width"] * .55))
    font_size = max(3, min(12, math.floor(model["cell_height"] / resolution) - 1))
    font = font_for(model.get("font", ""), font_size)
    advance = model.get('char_width') or max(1, font.getlength("M"))

    def band(first, last, color, left=0, right=width):
        top = max(0, round((first - 1 - origin) * line_height))
        bottom = min(height, round((last - origin) * line_height))
        if model.get("large") and 1 <= first <= model["count"]:
            bottom = min(height, max(top + 1, bottom))
        left, right = max(0, min(width, left)), max(0, min(width, right))
        if bottom > top and right > left:
            draw.rectangle((max(0, left), top, min(width, right) - 1, bottom - 1), fill=rgb(color))

    if shadows:
        band(model["viewport"][0], model["viewport"][1], model["view_background"])
    selection = model.get("selection")
    if shadows and selection:
        first = max(origin + 1, selection["first"])
        last = min(origin + math.ceil(height / line_height), selection["last"])
        for line in range(first, last + 1):
            left, right = 0, width
            if selection["kind"] == "block":
                left = math.floor(padding + selection["start_col"] * advance)
                right = math.ceil(padding + selection["end_col"] * advance)
            elif selection["kind"] == "char":
                if line == selection["first"]:
                    left = math.floor(padding + selection["start_col"] * advance)
                if line == selection["last"]:
                    right = math.ceil(padding + selection["end_col"] * advance)
            band(line, line, model["active_background"], left, right)
    elif shadows:
        band(model["cursor"], model["cursor"], model["active_background"])

    layer = glyphs(model, width, height, line_height, padding, font_size, font, advance)
    image.paste(layer, (0, 0), layer)
    for item in model.get("diagnostics", []):
        y = int((item["line"] - 1 - origin + .5) * line_height)
        if 0 <= y < height:
            draw.ellipse((width - 5, y - 1, width - 3, y + 1), fill=rgb(item["color"]))
    return image


def ink_tiles(model):
    canvas = render(model, shadows=False)
    step = model['cell_height']
    return [sixel(canvas.crop((0, y, canvas.width, min(y + step, canvas.height))), model['background'])
            for y in range(0, canvas.height, step)]


def sixel(image, background=None):
    # Quantise anti-aliasing colours, not characters.
    indexed = image.quantize(colors=64, dither=Image.Dither.NONE)
    palette, width, height = indexed.getpalette(), indexed.width, indexed.height
    pixels = indexed.load()
    colors = sorted({pixels[x, y] for y in range(height) for x in range(width)})
    transparent = None
    if background is not None:
        transparent = min(colors, key=lambda c: sum(abs(palette[c * 3 + n] - rgb(background)[n]) for n in range(3)))
    result = ['\x1bP0;1q', f'"1;1;{width};{height}']
    for color in colors:
        channels = palette[color * 3:color * 3 + 3]
        result.append(f'#{color};2;' + ';'.join(str(round(c * 100 / 255)) for c in channels))
    for top in range(0, height, 6):
        bands = {}
        for y in range(top, min(top + 6, height)):
            flag = 1 << (y - top)
            for x in range(width):
                color = pixels[x, y]
                if color == transparent:
                    continue
                masks = bands.get(color)
                if masks is None:
                    masks = bands[color] = bytearray(width)
                masks[x] |= flag
        for color, masks in sorted(bands.items()):
            result.append(f'#{color}')
            last = max(i for i, value in enumerate(masks) if value) + 1
            start = 0
            while start < last:
                end = start + 1
                while end < last and masks[end] == masks[start]:
                    end += 1
                char, amount = chr(63 + masks[start]), end - start
                result.append(f'!{amount}{char}' if amount >= 4 else char * amount)
                start = end
            result.append('$')
        if top + 6 < height:
            result.append('-')
    result.append('\x1b\\')
    return ''.join(result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--png", type=Path)
    args = parser.parse_args()
    if args.worker:
        for line in sys.stdin:
            request = None
            try:
                request = json.loads(line)
                model = request["model"]
                response = {"id": request["id"], "tiles": ink_tiles(model)}
            except Exception as error:
                response = {"id": (request or {}).get("id"), "error": str(error)}
            print(json.dumps(response, ensure_ascii=True), flush=True)
    else:
        model = json.load(sys.stdin)
        canvas = render(model)
        if args.png:
            canvas.save(args.png)
        else:
            sys.stdout.write(sixel(canvas, model["background"]))


if __name__ == "__main__":
    main()
