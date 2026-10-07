#!/usr/bin/env python3
"""Rasterize original COLR chrome into transparent Kitty PNG overlays.

The terminal renders ordinary text. Only cells containing Workbench geometry
are painted here, so this does not depend on terminal COLR or mark shaping.
"""
import base64
import cairo
from functools import lru_cache
import io
import json
from pathlib import Path
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
PATHS=json.loads((ROOT/'fonts/geometry-paths.json').read_text())

@lru_cache(maxsize=2048)
def cell(text,width,height,columns,fg,bg,bold,italic):
    # Render at 4x resolution for smooth, full-height curves on low-DPI screens.
    scale=4
    image=Image.new('RGBA',(width*columns*scale,height*scale))
    # Ordinary characters remain native terminal text, including CJK fallback.
    surface=cairo.ImageSurface(cairo.FORMAT_ARGB32,width*columns*scale,height*scale)
    ctx=cairo.Context(surface)
    for char in text:
        data=PATHS.get(str(ord(char)))
        if not data:continue
        ctx.save()
        span=data['top']-data['bottom']
        ctx.translate(0,height*scale*data['top']/span)
        ctx.scale(width*scale/600,-height*scale/span)
        for layer in data['layers']:
            ctx.new_path()
            for op,*points in layer['path']:
                if op=='M':ctx.move_to(*points)
                elif op=='L':ctx.line_to(*points)
                elif op=='C':ctx.curve_to(*points)
                elif op=='Z':ctx.close_path()
            ctx.set_source_rgba(*(v/255 for v in layer['color']))
            ctx.fill()
        ctx.restore()
    output=io.BytesIO();surface.write_to_png(output);output.seek(0)
    image.alpha_composite(Image.open(output).convert("RGBA"))
    return image.resize((width*columns,height),Image.Resampling.LANCZOS)


def render(model):
    cw,ch=model['cell_width'],model['cell_height']
    width,height=model['columns']*cw,model['rows']*ch
    if not 1<=width<=16384 or not 1<=height<=16384 or width*height>32000000:
        raise ValueError('Chrome canvas out of bounds')
    canvas=Image.new('RGBA',(width,height))
    for c in model['cells']:
        tile=cell(c['text'],cw,ch,c['width'],c['fg'],c['bg'],c.get('bold',False),c.get('italic',False))
        canvas.alpha_composite(tile,(c['col']*cw,c['row']*ch))
    output=io.BytesIO();canvas.save(output,format='PNG')
    return base64.b64encode(output.getvalue()).decode('ascii')

def main():
    for line in sys.stdin:
        request={}
        try:
            request=json.loads(line)
            result={'id':request['id'],'png':render(request['model'])}
        except Exception as error:
            result={'id':request.get('id'),'error':str(error)}
        print(json.dumps(result),flush=True)

if __name__=='__main__':
    main()
