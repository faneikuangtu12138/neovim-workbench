#!/usr/bin/env python3
"""Build Arch terminal fonts and vector chrome from shipped Geometry 6 TTFs.

Requires fontTools only while building. Does not install fonts or change settings.
The derivatives retain the original font and icon licenses in fonts/.
"""
import json
import math
from pathlib import Path
import re
from fontTools.ttLib import TTFont
from fontTools.pens.basePen import BasePen
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = Path(__file__).resolve().parents[1]

class OutlinePen(BasePen):
    def __init__(self, glyphs):
        super().__init__(glyphs)
        self.commands = []
    def _moveTo(self, p):
        self.commands.append(['M', *p])
    def _lineTo(self, p):
        self.commands.append(['L', *p])
    def _curveToOne(self, a, b, c):
        self.commands.append(['C', *a, *b, *c])
    def _closePath(self):
        self.commands.append(['Z'])
    def _endPath(self):
        pass


def bounds(height):
    native = []
    for dpi in (96, 192):
        scale = 12 / 72 * dpi / 1000
        cell = math.floor(height / 100 * 1000 * scale + .5)
        baseline = math.floor(1020 * scale + (cell - 1320 * scale) / 2 + .5)
        native.append((baseline / scale, (baseline - cell) / scale))
    return min(p[0] for p in native) - .25, max(p[1] for p in native) + .25


def main():
    destination = ROOT / 'fonts' / 'arch-text'
    destination.mkdir(parents=True, exist_ok=True)
    console_destination = ROOT / 'fonts' / 'arch-console'
    console_destination.mkdir(parents=True, exist_ok=True)
    paths = {}
    for source in sorted((ROOT / 'fonts').glob('ForgeMonoGeometry6NF-*.ttf')):
        font = TTFont(source)
        console = TTFont(source)
        # VTE has no separate cell-height control. Bake the 1.42 em cell and
        # centered baseline into a renamed derivative, preserving COLR glyphs.
        console['hhea'].ascent, console['hhea'].descent = 1070, -350
        console['OS/2'].sTypoAscender, console['OS/2'].sTypoDescender = 1070, -350
        console['OS/2'].usWinAscent, console['OS/2'].usWinDescent = 1070, 350
        # COLR seams used only their final lower-stroke layer as a base glyph.
        # VTE clips color drawing to that base's bounds, losing upper shoulders
        # and vertical rails. Give the base the union of its existing layers.
        # Color paths, mappings, advances and mark anchors remain unchanged.
        console_glyphs = console.getGlyphSet()
        for name, layers in console['COLR'].ColorLayers.items():
            if '.seam_' in name:
                pen = TTGlyphPen(console_glyphs)
                for layer in layers:
                    pen.addComponent(layer.name, (1, 0, 0, 1, 0, 0))
                glyph = pen.glyph()
                glyph.recalcBounds(console['glyf'])
                console['glyf'][name] = glyph
                advance, _ = console['hmtx'][name]
                console['hmtx'][name] = (advance, glyph.xMin)
        for record in console['name'].names:
            text = record.toUnicode().replace('ForgeMono Geometry 6 NF', 'ForgeMono Workbench Console NF').replace('ForgeMonoGeometry6NF', 'ForgeMonoWorkbenchConsoleNF')
            record.string = text.encode(record.getEncoding())
        console.save(console_destination / source.name.replace('Geometry6', 'WorkbenchConsole'))
        if source.stem.endswith('-Regular'):
            glyphs = font.getGlyphSet()
            for cp, name in font.getBestCmap().items():
                layers = font['COLR'].ColorLayers.get(name)
                if not layers:
                    continue
                match = re.search(r'\.h(\d+)\.', name)
                top, bottom = bounds(int(match[1]) if match else 142)
                entry = {'top': top, 'bottom': bottom, 'layers': []}
                for layer in layers:
                    pen = OutlinePen(glyphs)
                    glyphs[layer.name].draw(pen)
                    color = font['CPAL'].palettes[0][layer.colorID]
                    entry['layers'].append(dict(color=[color.red, color.green, color.blue, color.alpha], path=pen.commands))
                paths[str(cp)] = entry
        for name in font['COLR'].ColorLayers:
            font['glyf'][name] = TTGlyphPen(None).glyph()
        del font['COLR']
        del font['CPAL']
        for record in font['name'].names:
            text = record.toUnicode().replace('ForgeMono Geometry 6 NF', 'ForgeMono Workbench Text NF').replace('ForgeMonoGeometry6NF', 'ForgeMonoWorkbenchTextNF')
            record.string = text.encode(record.getEncoding())
        font.save(destination / source.name.replace('Geometry6', 'WorkbenchText'))
    if len(paths) != 1176:
        raise RuntimeError(f'Unexpected geometry glyph count: {len(paths)}')
    (ROOT / 'fonts' / 'geometry-paths.json').write_text(json.dumps(paths, separators=(',', ':')))
    print(f'Built four Text / four Console styles and {len(paths)} geometry glyphs')

if __name__ == '__main__':
    main()
