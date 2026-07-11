import os
from PIL import Image, ImageDraw

os.makedirs('assets/icon', exist_ok=True)
W = 1024
img = Image.new('RGB', (W, W), (46, 125, 50))
d = ImageDraw.Draw(img)
white = (255, 255, 255)


def t(p):
    return ((p[0] - 512) * 0.82 + 512, (p[1] - 540) * 0.82 + 512)


lw = 30
for cx in (330, 694):
    c = t((cx, 660))
    r = 150 * 0.82
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=white, width=lw)

RW, FW, BB, ST, HT = (330, 660), (694, 660), (500, 660), (430, 420), (640, 420)
for a, b in [(RW, BB), (BB, ST), (ST, HT), (HT, BB), (RW, ST), (HT, FW)]:
    d.line([t(a), t(b)], fill=white, width=lw, joint='curve')
d.line([t((392, 415)), t((468, 415))], fill=white, width=lw)
d.line([t((640, 420)), t((705, 392))], fill=white, width=lw)
d.line([t((688, 378)), t((722, 408))], fill=white, width=lw)
img.save('assets/icon/icon.png')

open('flutter_launcher_icons.yaml', 'w').write('''flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/icon/icon.png"
  adaptive_icon_background: "#2E7D32"
  adaptive_icon_foreground: "assets/icon/icon.png"
  min_sdk_android: 24
''')
print('icon + config 생성 완료')
