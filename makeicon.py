"""런처 아이콘 생성.

적응형 아이콘(Android 8+)은 전경 레이어의 바깥 1/3이 마스크에 잘린다.
그래서 전경(icon_fg)은 안전영역(가운데 ~66%)에 맞춰 그리고, 잘리지 않는
일반/스토어 아이콘(icon)은 꽉 채워 크게 그린다. 같은 파일을 둘 다 쓰면
어느 한쪽이 손해를 본다.
"""

import os
from PIL import Image, ImageDraw

os.makedirs('assets/icon', exist_ok=True)

W = 1024
GREEN = (46, 125, 50)
WHITE = (255, 255, 255)

# 자전거를 (512, 540) 중심으로 그린 원본 좌표계
RW, FW = (330, 660), (694, 660)                   # 뒷바퀴 / 앞바퀴 중심
BB, ST, HT = (500, 660), (430, 420), (640, 420)   # 크랭크 / 안장 / 핸들
WHEEL_R = 150


def draw_bike(img, scale, stroke):
    d = ImageDraw.Draw(img)

    def t(p):
        return ((p[0] - 512) * scale + 512, (p[1] - 540) * scale + 512)

    for c in (RW, FW):
        cx, cy = t(c)
        r = WHEEL_R * scale
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=WHITE, width=stroke)

    for a, b in [(RW, BB), (BB, ST), (ST, HT), (HT, BB), (RW, ST), (HT, FW)]:
        d.line([t(a), t(b)], fill=WHITE, width=stroke, joint='curve')

    d.line([t((392, 415)), t((468, 415))], fill=WHITE, width=stroke)   # 안장
    d.line([t((640, 420)), t((705, 392))], fill=WHITE, width=stroke)   # 핸들바
    d.line([t((688, 378)), t((722, 408))], fill=WHITE, width=stroke)   # 핸들 그립


# 일반 아이콘은 잘리지 않으니 여백을 거의 없앤다.
icon = Image.new('RGB', (W, W), GREEN)
draw_bike(icon, scale=1.20, stroke=62)
icon.save('assets/icon/icon.png')

# 적응형 전경은 가운데 원(지름 66%) 밖이 잘린다. scale 0.90이면 바퀴 바깥이
# 중심에서 32.7% 지점 → 안전선(33.3%) 안쪽 한계치.
fg = Image.new('RGBA', (W, W), (0, 0, 0, 0))
draw_bike(fg, scale=0.90, stroke=56)
fg.save('assets/icon/icon_fg.png')

open('flutter_launcher_icons.yaml', 'w').write('''flutter_launcher_icons:
  android: true
  ios: false
  image_path: "assets/icon/icon.png"
  adaptive_icon_background: "#2E7D32"
  adaptive_icon_foreground: "assets/icon/icon_fg.png"
  min_sdk_android: 24
''')
print('icon.png / icon_fg.png / flutter_launcher_icons.yaml 생성 완료')
