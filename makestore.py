import os
from PIL import Image, ImageDraw, ImageFont

GREEN = (46, 125, 50)
WHITE = (255, 255, 255)
FONT = "NanumGothicBold.ttf"


def draw_bike(d, cx, cy, scale, lw):
    def t(p):
        return (cx + (p[0] - 512) * scale, cy + (p[1] - 540) * scale)
    for wx in (330, 694):
        c = t((wx, 660)); r = 150 * scale
        d.ellipse([c[0]-r, c[1]-r, c[0]+r, c[1]+r], outline=WHITE, width=lw)
    RW, FW, BB, ST, HT = (330,660),(694,660),(500,660),(430,420),(640,420)
    for a, b in [(RW,BB),(BB,ST),(ST,HT),(HT,BB),(RW,ST),(HT,FW)]:
        d.line([t(a), t(b)], fill=WHITE, width=lw, joint='curve')
    d.line([t((392,415)), t((468,415))], fill=WHITE, width=lw)
    d.line([t((640,420)), t((705,392))], fill=WHITE, width=lw)
    d.line([t((688,378)), t((722,408))], fill=WHITE, width=lw)


# 1) 512 아이콘
ic = Image.new('RGB', (512, 512), GREEN)
draw_bike(ImageDraw.Draw(ic), 256, 250, 0.41, 16)
ic.save('icon_512.png')

# 2) 1024x500 피처 그래픽
fg = Image.new('RGB', (1024, 500), GREEN)
d = ImageDraw.Draw(fg)
draw_bike(d, 235, 250, 0.44, 17)
title = ImageFont.truetype(FONT, 82)
sub = ImageFont.truetype(FONT, 40)
d.text((430, 165), "따릉이 도우미", font=title, fill=WHITE)
d.text((432, 275), "반납 알림 · 내 주변 대여소", font=sub, fill=(220, 240, 220))
fg.save('feature.png')
print('saved both')
