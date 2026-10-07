"""Check the real vector chrome renderer, including the missing COLR join."""
import base64
import importlib.util
import io
from pathlib import Path
import unittest
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('geometry',ROOT/'scripts/geometry-render.py')
geometry=importlib.util.module_from_spec(spec);spec.loader.exec_module(geometry)

class GeometryTests(unittest.TestCase):
    def test_selected_tab_join_contains_blue_stroke_at_low_and_high_dpi(self):
        for cw,ch in [(10,24),(23,54)]:
            image=geometry.cell(chr(58407),cw,ch,1,0xcad3f5,0x24273a,False,False)
            blue=lambda p:p[2]>p[0]+30 and p[1]>p[0]+15
            self.assertTrue(any(blue(p) for p in image.get_flattened_data()))
            self.assertTrue(any(blue(image.getpixel((cw-1,y))) for y in range(ch-4,ch)))

    def test_every_exported_geometry_glyph_accepts_cairo_png_modes(self):
        for cp in geometry.PATHS:
            with self.subTest(codepoint=cp):
                image=geometry.cell(chr(int(cp)),10,24,1,0xcad3f5,0x24273a,False,False)
                self.assertEqual(image.mode,'RGBA')
                self.assertEqual(image.size,(10,24))

    def test_geometry_image_does_not_cover_editor_text(self):
        model=dict(cell_width=10,cell_height=24,columns=80,rows=24,cells=[dict(row=0,col=0,text=chr(58398),width=1,fg=0xcad3f5,bg=0x24273a)])
        image=Image.open(io.BytesIO(base64.b64decode(geometry.render(model))))
        self.assertEqual(image.size,(800,576))
        self.assertEqual(image.getpixel((100,100))[3],0)
        self.assertEqual(image.getpixel((5,12))[3],0)
        self.assertIsNotNone(image.getchannel("A").getbbox())

    def test_marks_leave_native_base_character_uncovered(self):
        mark=chr(7657)
        a=geometry.cell('A'+mark,10,24,1,0xcad3f5,0x24273a,False,False)
        b=geometry.cell('B'+mark,10,24,1,0xcad3f5,0x24273a,False,False)
        self.assertEqual(a.tobytes(),b.tobytes())
        self.assertEqual(a.getpixel((5,12))[3],0)
        self.assertTrue(any(p[2]>p[0]+30 for p in a.crop((0,0,10,3)).get_flattened_data()))

if __name__=='__main__':unittest.main()
