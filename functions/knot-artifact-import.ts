import type { KnotDocument } from './knot-documents';

export type ArtifactImportResource = { resource: number; size: number; sha256: string; path: string };
type Input = { messageID: string; sequence: number; offset: number; document: Pick<KnotDocument, 'id' | 'provenance'> };
function base64(bytes: Uint8Array): string { let result = ''; for (let i = 0; i < bytes.length; i += 8192) result += String.fromCharCode(...bytes.subarray(i, i + 8192)); return btoa(result); }

/** Fixed data-only transport. It never evaluates or launches the received file. */
export function artifactImportCommand(value: Input, resource?: ArtifactImportResource, chunk?: Uint8Array): string {
  const input = JSON.stringify({ id: value.messageID, documentID: value.document.id, sequence: value.sequence, provenance: value.document.provenance, resource, offset: value.offset, data: chunk ? base64(chunk) : undefined });
  // Every filesystem operation is relative to no-follow directory descriptors.
  // Exclusive links publish each verified original; conflicts never overwrite.
  return "command -p python3 -I - <<'WHISPER_EXACT_IMPORT'\n" + `import os, json, base64, hashlib, stat
v=json.loads(${JSON.stringify(input)})
flags=os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW
def directory(parent,name):
 try: os.mkdir(name,0o700,dir_fd=parent)
 except FileExistsError: pass
 return os.open(name,flags,dir_fd=parent)
def read(parent,name):
 fd=os.open(name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=parent)
 try:
  assert stat.S_ISREG(os.fstat(fd).st_mode) and os.fstat(fd).st_size<=50000000
  out=b''
  while True:
   b=os.read(fd,1048576)
   if not b: return out
   out+=b
   assert len(out)<=50000000
 finally: os.close(fd)
def exclusive(parent,name,data):
 try: fd=os.open(name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600,dir_fd=parent)
 except FileExistsError:
  assert read(parent,name)==data
  return
 with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
root=os.open('.',flags)
received=directory(root,'received')
folder=directory(received,v['id'])
r=v.get('resource')
if r:
 data=base64.b64decode(v['data'],validate=True)
 part='.whisper-part-'+str(r['resource'])
 fd=os.open(part,os.O_RDWR|os.O_NOFOLLOW|(os.O_CREAT|os.O_EXCL if v['offset']==0 else 0),0o600,dir_fd=folder)
 try:
  size=os.fstat(fd).st_size
  assert stat.S_ISREG(os.fstat(fd).st_mode) and os.fstat(fd).st_nlink==1 and size<=r['size']
  if size==v['offset']:
   assert os.pwrite(fd,data,v['offset'])==len(data)
   os.fsync(fd)
  else:
   assert size>=v['offset']+len(data) and os.pread(fd,len(data),v['offset'])==data
 finally: os.close(fd)
 if v['offset']+len(data)==r['size']:
  full=read(folder,part)
  assert len(full)==r['size'] and hashlib.sha256(full).hexdigest()==r['sha256']
  parent=folder
  names=r['path'].split('/')
  for name in names[:-1]: parent=directory(parent,name)
  try: os.link(part,names[-1],src_dir_fd=folder,dst_dir_fd=parent,follow_symlinks=False)
  except FileExistsError:
   existing=read(parent,names[-1])
   assert len(existing)==r['size'] and hashlib.sha256(existing).hexdigest()==r['sha256']
  os.fsync(parent)
  os.unlink(part,dir_fd=folder)
else:
 exclusive(folder,'.whisper-provenance.json',json.dumps(v['provenance'],ensure_ascii=False,sort_keys=True).encode())
exclusive(folder,'.whisper-receipt-'+str(v['sequence']),(v['documentID']+':'+str(v['sequence'])).encode())
os.fsync(folder)
print('WHISPER_EXACT_IMPORT_OK')
WHISPER_EXACT_IMPORT`;
}
