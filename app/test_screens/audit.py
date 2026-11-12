"""Checks the screenshot run: text contrast against the real pixels behind
it, text cut off by maxLines, and Bangla text set with tight line height.

  python3 test_screens/audit.py /path/to/shots
"""
import collections
import json
import pathlib
import re
import sys

from PIL import Image

DPR = 2.0
BN = re.compile('[\u0980-\u09FF]')


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c[:3]
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


def bg_of(img, rect):
    x, y, w, h = [v * DPR for v in rect]
    pts = []
    for px in range(int(x) - 3, int(x + w) + 3, 2):
        for py in (int(y) - 3, int(y + h) + 2):
            if 0 <= px < img.width and 0 <= py < img.height:
                pts.append(img.getpixel((px, py))[:3])
    for py in range(int(y), int(y + h), 2):
        for px in (int(x) - 3, int(x + w) + 2):
            if 0 <= px < img.width and 0 <= py < img.height:
                pts.append(img.getpixel((px, py))[:3])
    if not pts:
        return None
    return collections.Counter(pts).most_common(1)[0][0]


def main(d):
    d = pathlib.Path(d)
    problems = []
    for js in sorted(d.glob('*.json')):
        png = js.with_suffix('.png')
        img = Image.open(png).convert('RGB')
        items = json.load(open(js))
        vis = [t for t in items if t.get('visible')]
        W, H = img.width / DPR, img.height / DPR
        for i, a in enumerate(vis):
            ax, ay, aw, ah = a['rect']
            if ay > H or ay + ah < 0:
                continue
            if ax < -0.5 or ax + aw > W + 0.5:
                problems.append(f'{js.stem}: OFFSCREEN x={ax:.0f} w={aw:.0f} "{a["text"][:40]}"')
            for b in vis[i + 1:]:
                bx, by, bw, bh = b['rect']
                ox = min(ax + aw, bx + bw) - max(ax, bx)
                oy = min(ay + ah, by + bh) - max(ay, by)
                if ox > 2 and oy > 4:
                    problems.append(f'{js.stem}: OVERLAP "{a["text"][:30]}" / "{b["text"][:30]}" ({ox:.0f}x{oy:.0f})')
        for t in vis:
            x, y, w, h = t['rect']
            if w <= 0 or h <= 0 or y > img.height / DPR or x > img.width / DPR:
                continue
            if y + h < 0 or x + w < 0:
                continue
            txt = t['text'].replace('\n', ' ')
            if t['cut'] and (t['maxLines'] or 0) > 1:
                problems.append(f'{js.stem}: CUT ({t["maxLines"]} lines) "{txt[:50]}"')
            if t['color'] is not None:
                c = t['color']
                a = (c >> 24) & 255
                rgb = ((c >> 16) & 255, (c >> 8) & 255, c & 255)
                bg = bg_of(img, t['rect'])
                if bg and a > 0:
                    # Blend a translucent text colour over the background.
                    al = a / 255
                    rgb = tuple(round(rgb[i] * al + bg[i] * (1 - al)) for i in range(3))
                    cr = contrast(rgb, bg)
                    size = t['size'] or 14
                    need = 3.0 if size >= 18 else 4.5
                    if cr < need:
                        problems.append(
                            f'{js.stem}: CONTRAST {cr:.2f} (<{need}) size {size} '
                            f'fg #{"%02x%02x%02x" % rgb} bg #{"%02x%02x%02x" % bg} "{txt[:40]}"')
            if BN.search(t['text']) and t['size'] and t['height']:
                if t['height'] < 1.3:
                    problems.append(
                        f'{js.stem}: TIGHT Bangla line height {t["height"]:.2f} size {t["size"]} "{txt[:40]}"')
            if t['size'] and t['size'] < 11:
                problems.append(f'{js.stem}: TINY {t["size"]}px "{txt[:40]}"')
    seen = set()
    for p in problems:
        key = re.sub(r'^\S+: ', '', p)
        if key in seen:
            continue
        seen.add(key)
        print(p)
    print(len(problems), 'findings')


if __name__ == '__main__':
    main(sys.argv[1])
