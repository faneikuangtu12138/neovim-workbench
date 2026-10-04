"""Regressions for real glyphs, selection masks and the terminal image stream."""
import importlib.util
from pathlib import Path
import re
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("minimap_pixels", ROOT / "scripts/minimap-render.py")
pixels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixels)


def model():
    return dict(pixel_width=100, pixel_height=80, cell_width=10, cell_height=20,
                resolution=2, offset=0, count=8, viewport=[3, 6], cursor=4,
                background=0x24273A, view_background=0x2B2E43,
                active_background=0x1B1F32, characters=[], diagnostics=[],
                font=str(ROOT / "fonts/ForgeMonoGeometry6NF-Regular.ttf"))


def decode(stream):
    """Independent Sixel decoder: validate palette, run lengths and six-row bands."""
    assert stream.startswith('\x1bP0;1q') and stream.endswith('\x1b\\')
    data = stream[len('\x1bP0;1q'):-2]
    size = re.match(r'"\d+;\d+;(\d+);(\d+)', data)
    image = Image.new("RGBA", tuple(map(int, size.groups())))
    palette, color, x, y, i = {}, 0, 0, 0, size.end()
    while i < len(data):
        char = data[i]
        if char == '#':
            match = re.match(r'#(\d+)(?:;2;(\d+);(\d+);(\d+))?', data[i:])
            color = int(match[1])
            if match[2] is not None:
                palette[color] = tuple(round(int(match[n]) * 255 / 100) for n in (2, 3, 4)) + (255,)
            i += match.end()
            continue
        if char == '$':
            x, i = 0, i + 1
            continue
        if char == '-':
            y, x, i = y + 6, 0, i + 1
            continue
        count = 1
        if char == '!':
            match = re.match(r'!(\d+)([?-~])', data[i:])
            count, char, i = int(match[1]), match[2], i + match.end()
        else:
            i += 1
        mask = ord(char) - 63
        assert 0 <= mask <= 63
        for dx in range(count):
            for dy in range(6):
                if mask & (1 << dy):
                    assert x + dx < image.width and y + dy < image.height
                    image.putpixel((x + dx, y + dy), palette[color])
        x += count
    return image


class PixelMinimapTests(unittest.TestCase):
    def test_real_letters_instead_of_occupancy_blocks(self):
        a, b = model(), model()
        a['characters'] = [[dict(column=i, char=c, color=0xC6A0F6) for i, c in enumerate('wire')]]
        b['characters'] = [[dict(column=i, char=c, color=0xC6A0F6) for i, c in enumerate('fire')]]
        first, second = pixels.render(a), pixels.render(b)
        self.assertNotEqual(first.tobytes(), second.tobytes())
        ink = sum(first.getpixel((x, y)) != pixels.rgb(a['background']) for y in range(10) for x in range(24))
        self.assertGreater(ink, 10)
        self.assertLess(ink, 10 * 24 // 2)

    def test_view_shadow_and_exact_caret_line_without_left_ruler(self):
        m = model()
        image = pixels.render(m)
        for y in range(80):
            expected = m['active_background'] if 30 <= y < 40 else m['view_background'] if 20 <= y < 60 else m['background']
            self.assertEqual(image.getpixel((0, y)), pixels.rgb(expected))
            self.assertEqual(image.getpixel((99, y)), pixels.rgb(expected))

        # Reusing the glyph layer must not freeze cursor or viewport shadows.
        m.update(cursor=5, viewport=[4, 7])
        changed = pixels.render(m)
        self.assertEqual(changed.getpixel((0, 45)), pixels.rgb(m['active_background']))
        self.assertEqual(changed.getpixel((0, 25)), pixels.rgb(m['background']))

    def test_char_selection_covers_only_selected_columns(self):
        m = model()
        m['selection'] = dict(kind='char', first=3, last=3, start_col=2, end_col=5)
        image = pixels.render(m)
        advance = pixels.font_for(m['font'], 9).getlength('M')
        left, right = int(6 + 2 * advance), int(6 + 5 * advance)
        self.assertEqual(image.getpixel((0, 25)), pixels.rgb(m['view_background']))
        self.assertEqual(image.getpixel((left, 25)), pixels.rgb(m['active_background']))
        self.assertEqual(image.getpixel((right, 25)), pixels.rgb(m['view_background']))
        self.assertEqual(image.getpixel((0, 35)), pixels.rgb(m['view_background']))

    def test_multiline_char_line_and_block_selections(self):
        for kind in ('char', 'line', 'block'):
            with self.subTest(kind=kind):
                m = model()
                m['selection'] = dict(kind=kind, first=3, last=5, start_col=2, end_col=5)
                image = pixels.render(m)
                self.assertEqual(image.getpixel((25, 35)), pixels.rgb(m['active_background']))
                self.assertEqual(image.getpixel((0, 35)), pixels.rgb(m['view_background'] if kind == 'block' else m['active_background']))
                self.assertEqual(image.getpixel((0, 25)), pixels.rgb(m['view_background'] if kind != 'line' else m['active_background']))

    def test_selection_outside_preview_does_not_draw_or_raise(self):
        m = model()
        m['selection'] = dict(kind='block', first=1, last=8, start_col=100000, end_col=100003)
        image = pixels.render(m)
        self.assertEqual(image.getpixel((99, 35)), pixels.rgb(m['view_background']))

    def test_unicode_and_clipped_long_line(self):
        m = model()
        m['characters'] = [[dict(column=0, char='中', color=0x8AADF4), dict(column=2, char='é', color=0xA6DA95), dict(column=100000, char='x', color=0xA6DA95)]]
        self.assertEqual(pixels.render(m).size, (100, 80))

    def test_sixel_round_trip_preserves_shadows_and_transparent_base(self):
        m = model()
        image = pixels.render(m)
        decoded = decode(pixels.sixel(image, m['background']))
        for y in range(80):
            if y < 20 or y >= 60:
                self.assertEqual(decoded.getpixel((0, y))[3], 0)
            else:
                expected = image.getpixel((0, y))
                actual = decoded.getpixel((0, y))
                self.assertEqual(actual[3], 255)
                self.assertTrue(all(abs(a - b) <= 2 for a, b in zip(actual[:3], expected)))

    def test_sixel_partial_band_and_long_horizontal_runs(self):
        image = Image.new('RGB', (137, 17), (241, 200, 112))
        decoded = decode(pixels.sixel(image))
        self.assertEqual(decoded.size, image.size)
        self.assertEqual(decoded.getbbox(), (0, 0, 137, 17))
        self.assertTrue(all(abs(a - b) <= 2 for a, b in zip(decoded.getpixel((136, 16))[:3], image.getpixel((136, 16)))))

    def test_large_file_caret_is_at_least_one_pixel(self):
        m = model()
        m.update(large=True, count=100000, cursor=50000, viewport=[50000, 50035])
        image = pixels.render(m)
        self.assertIn(pixels.rgb(m['active_background']), set(image.get_flattened_data()))

    def test_canvas_bounds_are_enforced(self):
        for width, height in ((0, 80), (2049, 80), (100, 4097)):
            m = model()
            m.update(pixel_width=width, pixel_height=height)
            with self.assertRaises(ValueError):
                pixels.render(m)


if __name__ == '__main__':
    unittest.main()
