"""Generates the Diffcat icon SVGs. Art is drawn in a 1000-unit box centred on (500, 483)."""
import sys, os
out = sys.argv[1]

INK = '#0d1117'
RED = '#f85149'
GREEN = '#3fb950'
WHITE = '#ffffff'

HEAD = f'''
  <ellipse cx="500" cy="560" rx="300" ry="262"/>
  <path d="M232 470 L258 168 L452 318 Z" stroke-linejoin="round" stroke-width="56"/>
  <path d="M768 470 L742 168 L548 318 Z" stroke-linejoin="round" stroke-width="56"/>'''

def inner_ears(fill):
    return f'''
  <path d="M272 400 L286 252 L392 330 Z" fill="{fill}" stroke="{fill}" stroke-linejoin="round" stroke-width="24"/>
  <path d="M728 400 L714 252 L608 330 Z" fill="{fill}" stroke="{fill}" stroke-linejoin="round" stroke-width="24"/>'''

WHISKERS = f'''
  <g stroke="{WHITE}" stroke-width="18" stroke-linecap="round" fill="none">
    <path d="M210 628 L112 606"/><path d="M212 668 L118 684"/>
    <path d="M790 628 L888 606"/><path d="M788 668 L882 684"/>
  </g>'''

def face(lens_fill, ring_l, ring_r, ink):
    return f'''
  <g stroke-linecap="round" fill="none">
    <path d="M276 528 L214 500" stroke="{ink}" stroke-width="20"/>
    <path d="M724 528 L786 500" stroke="{ink}" stroke-width="20"/>
    <path d="M468 528 Q500 500 532 528" stroke="{ink}" stroke-width="22"/>
  </g>
  <circle cx="374" cy="542" r="98" fill="{lens_fill}" stroke="{ring_l}" stroke-width="28"/>
  <circle cx="626" cy="542" r="98" fill="{lens_fill}" stroke="{ring_r}" stroke-width="28"/>
  <g stroke-linecap="round" stroke-width="30" fill="none">
    <path d="M330 542 L418 542" stroke="{ring_l}"/>
    <path d="M582 542 L670 542 M626 498 L626 586" stroke="{ring_r}"/>
  </g>
  <path d="M478 656 L522 656 L500 682 Z" fill="{ink}" stroke="{ink}" stroke-width="14" stroke-linejoin="round"/>
  <path d="M456 708 Q478 734 500 708 Q522 734 544 708" stroke="{ink}" stroke-width="14" stroke-linecap="round" fill="none"/>'''

def art(scale, cx=512, cy=512):
    return f'''<g transform="translate({cx} {cy}) scale({scale}) translate(-500 -483)">
  <ellipse cx="500" cy="840" rx="250" ry="26" fill="#000" opacity="0.18"/>
  <g fill="#f6f8fa" stroke="#f6f8fa">{HEAD}</g>{inner_ears('#d8c7ff')}{WHISKERS}{face(INK, RED, GREEN, INK)}
</g>'''

BG_DEFS = '''<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#8957e5"/>
    <stop offset="0.55" stop-color="#4c2f9e"/>
    <stop offset="1" stop-color="#1b1446"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.45" r="0.5">
    <stop offset="0" stop-color="#b392f0" stop-opacity="0.55"/>
    <stop offset="1" stop-color="#b392f0" stop-opacity="0"/>
  </radialGradient>
</defs>
<rect width="1024" height="1024" fill="url(#bg)"/>
<circle cx="512" cy="480" r="470" fill="url(#glow)"/>'''

def svg(body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\n{body}\n</svg>\n'

# Full-bleed square for iOS / legacy Android / README (platforms apply their own mask).
open(os.path.join(out, 'icon.svg'), 'w').write(svg(BG_DEFS + '\n' + art(0.92, cy=500)))
# Android adaptive: 108dp canvas, everything must sit in the central 66dp circle.
open(os.path.join(out, 'foreground.svg'), 'w').write(svg(art(0.75)))
open(os.path.join(out, 'background.svg'), 'w').write(svg(BG_DEFS))
# Android 13 themed icon: single colour, shape carried by alpha. Features are cut out.
mono = f'''<defs><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
  <g fill="#fff" stroke="#fff">{HEAD}</g>{WHISKERS}{face('#000', '#000', '#000', '#000')}
  <g stroke-linecap="round" stroke-width="30" stroke="#fff" fill="none">
    <path d="M330 542 L418 542"/><path d="M582 542 L670 542 M626 498 L626 586"/>
  </g>
</mask></defs>
<g transform="translate(512 512) scale(0.75) translate(-500 -483)">
  <rect x="0" y="0" width="1000" height="1000" fill="#fff" mask="url(#m)"/>
</g>'''
open(os.path.join(out, 'monochrome.svg'), 'w').write(svg(mono))
