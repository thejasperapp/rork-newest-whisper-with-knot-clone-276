"""Derive theme-aware backgrounds from supplied pixels; never redraw Knot.
Requires Pillow, numpy, opencv-python-headless. Originals remain untouched.
Run with PYTHONPATH pointing at an isolated dependency directory if needed.
"""
from pathlib import Path
import json, subprocess
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / 'ios/Whisper/WhisperFitnessApp/Resources/KnotAvatarV4'
ASSETS = ROOT / 'ios/Whisper/WhisperFitnessApp/Assets.xcassets'

def composite(rgb, light, keep_glow=False):
    f = rgb.astype(np.float32)
    hi, lo = f.max(2), f.min(2)
    # The knitted charcoal silhouette is neutral and dark. Fill enclosed eyes
    # after contour extraction so their original orange pixels remain intact.
    core = ((hi > 9) & (hi < 140) & ((hi-lo) < hi * .42)).astype(np.uint8) * 255
    # Close gaps between knitted stitches before filling the silhouette. This
    # connects the charcoal material without changing any subject colour pixels.
    k = max(5, int(min(rgb.shape[:2]) * .016) | 1)
    core = cv2.morphologyEx(core, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(k,k)))
    contours, _ = cv2.findContours(core, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    mask = np.zeros(core.shape, np.uint8)
    if not contours:
        raise RuntimeError('No supplied silhouette found')
    largest = max(contours, key=cv2.contourArea)
    if cv2.contourArea(largest) < rgb.shape[0]*rgb.shape[1]*.03:
        raise RuntimeError('Supplied silhouette too small')
    cv2.drawContours(mask, [largest], -1, 255, cv2.FILLED)
    # Eyes can reach the outer contour during turns. Recover their compact
    # luminous components, not a convex hull that would retain ambient halo.
    eye_pixels = ((f[:,:,0] > 145) & (f[:,:,1] > 70) & (f[:,:,1] > f[:,:,2]*1.4)).astype(np.uint8)
    count, labels, stats, centers = cv2.connectedComponentsWithStats(eye_pixels)
    x,y,w,h = cv2.boundingRect(largest)
    for index in range(1,count):
        ex,ey,ew,eh,area = stats[index]
        cx,cy = centers[index]
        if (area > w*h*.004 and area/(ew*eh) > .60 and .25 < ew/eh < 2.5
                and x+w*.2 < cx < x+w*.8 and y < cy < y+h*.72):
            eye = (labels == index).astype(np.uint8)*255
            eye_edge = max(9, int(w*.08) | 1)
            eye = cv2.dilate(eye, cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(eye_edge,eye_edge)))
            mask = cv2.bitwise_or(mask, eye)
    alpha = cv2.GaussianBlur(mask.astype(np.float32)/255, (3,3), .6)[...,None]
    bg = 255 if light else 0
    if keep_glow:
        # Orb film has a black, premultiplied glow. Preserve that effect rather
        # than applying the silhouette-only treatment used by all other states.
        outside = np.maximum(f - 5, 0)
        glow = np.clip(outside.max(2, keepdims=True)/230, 0, 1)
        glow_alpha = np.maximum(alpha, glow)
        result = f + bg*(1-glow_alpha) if light else f
    else:
        result = f*alpha + bg*(1-alpha)
    return np.clip(result,0,255).astype(np.uint8)

def stills():
    for source in MEDIA.glob('knot-avatar*.webp'):
        state = source.stem.removeprefix('knot-avatar').lstrip('-') or 'master'
        if state == 'darkmode':
            continue
        rgb = np.array(Image.open(source).convert('RGB'))
        for theme in ['light', 'dark']:
            folder = ASSETS / f'KnotClean-{theme}-{state}.imageset'
            folder.mkdir(exist_ok=True)
            # Stills retain supplied subject/eyes, removing baked ambient halo.
            Image.fromarray(composite(rgb, theme=='light')).save(folder/'poster.png')
            (folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'poster.png','idiom':'universal'}], 'info':{'author':'xcode','version':1}},indent=2)+'\n')

def films():
    for source in [*sorted(MEDIA.glob('anim-*.mp4')), MEDIA/'dance-6.mp4']:
        cap = cv2.VideoCapture(str(source))
        width,height = int(cap.get(3)),int(cap.get(4))
        fps = cap.get(cv2.CAP_PROP_FPS)
        if not width or not fps:
            raise RuntimeError('Unreadable supplied film')
        state = source.stem.removeprefix('anim-')
        players = {}
        for theme in ['light','dark']:
            path = MEDIA/f'clean-{theme}-{state}.mp4'
            players[theme] = subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pixel_format','rgb24','-video_size',f'{width}x{height}','-framerate',str(fps),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-threads','2','-pix_fmt','yuv420p','-movflags','+faststart',str(path)], stdin=subprocess.PIPE)
        count=0
        while True:
            ok,bgr=cap.read()
            if not ok: break
            rgb=cv2.cvtColor(bgr,cv2.COLOR_BGR2RGB)
            for theme,player in players.items():
                player.stdin.write(composite(rgb,theme=='light',state=='making-something').tobytes())
            count+=1
        cap.release()
        for player in players.values():
            player.stdin.close()
            if player.wait()!=0: raise RuntimeError('Avatar encoding failed')
        print(f'{state}: {count} supplied frames, two theme backgrounds',flush=True)

def review(destination):
    """Sample every derived film at 0, 2, 4 and 6 seconds for human review."""
    from PIL import ImageDraw
    paths = sorted(MEDIA.glob('clean-*.mp4'))
    sheet = Image.new('RGB', (960, len(paths)*270), '#888888')
    draw = ImageDraw.Draw(sheet)
    for row, path in enumerate(paths):
        cap = cv2.VideoCapture(str(path))
        for column, second in enumerate([0, 2, 4, 6]):
            cap.set(cv2.CAP_PROP_POS_MSEC, second*1000)
            ok, frame = cap.read()
            if not ok: raise RuntimeError(f'Unreadable sample: {path.name} {second}')
            image = Image.fromarray(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)).resize((240,240))
            sheet.paste(image, (column*240,row*270+30))
            draw.text((column*240+4,row*270+6), f'{path.stem} / {second}s', fill='white')
        cap.release()
    sheet.save(destination)

if __name__ == '__main__':
    import sys
    if len(sys.argv) == 3 and sys.argv[1] == '--review':
        review(sys.argv[2])
    else:
        stills()
        films()
