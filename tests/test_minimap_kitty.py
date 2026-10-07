"""Decode actual Kitty payloads and compare pixels against the independent renderer."""
import base64
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import zlib
from PIL import Image
from test_minimap_pixels import model, pixels, ROOT


class KittyMinimapTests(unittest.TestCase):
    def test_transparent_png_preserves_real_ink_and_alpha(self):
        m=model()
        m.update(protocol='kitty',char_width=2)
        m['characters']=[[dict(column=i,char=c,color=0xC6A0F6) for i,c in enumerate('wire value = 42;')]]
        before=pixels.ink_tiles(m)
        tile=Image.open(io.BytesIO(base64.b64decode(before[0])))
        self.assertEqual(tile.mode,'RGBA')
        self.assertEqual(tile.size,(100,20))
        alpha=tile.getchannel('A')
        self.assertEqual(alpha.getpixel((99,19)),0)
        self.assertTrue(any(0<a<255 for a in alpha.get_flattened_data()))
        m.update(cursor=6,selection=dict(kind='block',first=1,last=7,start_col=1,end_col=8))
        self.assertEqual(before,pixels.ink_tiles(m))
        m['characters'][0][0]['char']='f'
        self.assertNotEqual(before,pixels.ink_tiles(m))

    def test_shade_pixels_match_all_selection_modes_at_physical_dpi(self):
        cases=[]
        for width,height in [(10,20),(23,54)]:
            for selection in [None,dict(kind='line',first=2,last=6,start_col=0,end_col=1),
                              dict(kind='char',first=2,last=7,start_col=4,end_col=3),
                              dict(kind='block',first=2,last=7,start_col=2,end_col=5),
                              dict(kind='block',first=1,last=8,start_col=10000,end_col=10003)]:
                m=model()
                m.update(cell_width=width,cell_height=height,pixel_width=width*10,pixel_height=height*4,
                         char_width=2*width/10,resolution=3)
                if selection:m['selection']=selection
                cases.append(m)
        with tempfile.TemporaryDirectory() as directory:
            source=Path(directory)/'models.json'; source.write_text(json.dumps(cases))
            data=subprocess.check_output(['nvim','--clean','--headless','-l',str(ROOT/'tests/minimap_kitty_fixture.lua'),str(source)])
        for m,tiles in zip(cases,json.loads(data)):
            image=Image.new('RGB',(m['pixel_width'],m['pixel_height']))
            for row,tile in enumerate(tiles):
                raw=base64.b64decode(tile['data'])
                if tile['compressed']:raw=zlib.decompress(raw)
                stripe=Image.frombytes('RGB',(m['pixel_width'],m['cell_height']),raw)
                image.paste(stripe,(0,row*m['cell_height']))
            self.assertEqual(image.tobytes(),pixels.render(m).tobytes())


if __name__=='__main__':unittest.main()
