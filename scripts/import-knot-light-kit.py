"""Import the supplied white-background kit unchanged; no matte or transcoding.
Usage: python scripts/import-knot-light-kit.py <unpacked kit> <review jpg>
"""
from pathlib import Path
import sys, shutil, hashlib, json, subprocess
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1])
destination = root/'ios/Whisper/WhisperFitnessApp/Resources/KnotAvatarLightV5'
destination.mkdir(exist_ok=True)
receipts = []
for name in ['knot-avatar-master.jpg', *[f'anim-light-{state}.mp4' for state in ['milestone','making-something','idle','working']]]:
    data = (source/name).read_bytes()
    shutil.copyfile(source/name, destination/name)
    assert (destination/name).read_bytes() == data
    receipts.append({'name':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'byteIdentical':True})
folder = root/'ios/Whisper/WhisperFitnessApp/Assets.xcassets/KnotLightV5-master.imageset'
folder.mkdir(exist_ok=True)
shutil.copyfile(source/'knot-avatar-master.jpg',folder/'knot-avatar-master.jpg')
(folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'knot-avatar-master.jpg','idiom':'universal'}],'info':{'author':'xcode','version':1}},indent=2)+'\n')
(destination/'import-receipts.json').write_text(json.dumps(receipts,indent=2)+'\n')
# Review frames only; copied runtime files remain byte-identical.
sheet = Image.new('RGB',(960,5*265),'white')
draw = ImageDraw.Draw(sheet)
for row,state in enumerate(['milestone','making-something','idle','working']):
    for col,second in enumerate([0,1,2,4]):
        result = subprocess.run(['ffmpeg','-v','error','-ss',str(second),'-i',str(source/f'anim-light-{state}.mp4'),'-frames:v','1','-f','image2pipe','-vcodec','png','-'],capture_output=True,check=True)
        import io
        frame = Image.open(io.BytesIO(result.stdout)).convert('RGB').resize((240,240))
        sheet.paste(frame,(col*240,row*265+25))
        draw.text((col*240+5,row*265+5),f'{state} / {second}s',fill='black')
sheet.paste(Image.open(source/'knot-avatar-master.jpg').convert('RGB').resize((240,240)),(360,4*265+25))
sheet.save(sys.argv[2])
print(json.dumps(receipts,indent=2))
