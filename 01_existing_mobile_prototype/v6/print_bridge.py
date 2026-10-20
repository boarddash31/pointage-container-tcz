"""Local-only IPP PDF printing bridge. Run python print_bridge.py on same PC as browser.
Requires a PDF-capable IPP printer (usually port 631). No third-party modules.
"""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from urllib.request import Request, urlopen
import ipaddress, struct, json, time

PORT=8765
MAX_BYTES=2_000_000

def ipp_str(tag,name,value):
    nb=name.encode(); vb=value.encode(); return bytes([tag])+struct.pack('>H',len(nb))+nb+struct.pack('>H',len(vb))+vb

def print_ipp(ip,path,pdf):
    addr=ipaddress.ip_address(ip)
    if not addr.is_private: raise ValueError('Only private LAN addresses are allowed')
    if not path.startswith('/') or '//' in path or '?' in path or '#' in path:raise ValueError('Invalid IPP path')
    uri=f'ipp://{ip}:631{path}'
    data=b'\x01\x01'+struct.pack('>H',2)+struct.pack('>I',int(time.time())&0xffffffff)+b'\x01'
    data+=ipp_str(0x47,'attributes-charset','utf-8')
    data+=ipp_str(0x48,'attributes-natural-language','en')
    data+=ipp_str(0x45,'printer-uri',uri)
    data+=ipp_str(0x42,'requesting-user-name','pointage')
    data+=ipp_str(0x42,'job-name','Pointage Container Bon')
    data+=ipp_str(0x49,'document-format','application/pdf')+b'\x03'+pdf
    req=Request(f'http://{ip}:631{path}',data=data,headers={'Content-Type':'application/ipp'},method='POST')
    with urlopen(req,timeout=8) as r:response=r.read(1024)
    if len(response)<4:raise RuntimeError('Invalid IPP response')
    status=struct.unpack('>H',response[2:4])[0]
    if status>=0x0400:raise RuntimeError(f'IPP rejected job: 0x{status:04X} (check IPP path and PDF support)')
    return status

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def headers_out(self):
        self.send_header('Access-Control-Allow-Origin','*')
        self.send_header('Access-Control-Allow-Methods','POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers','Content-Type')
        self.send_header('Access-Control-Allow-Private-Network','true')
    def send_json(self,status,obj):
        b=json.dumps(obj).encode();self.send_response(status);self.headers_out();self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
    def do_OPTIONS(self):self.send_response(204);self.headers_out();self.end_headers()
    def do_POST(self):
        try:
            if urlparse(self.path).path!='/print':raise ValueError('Unknown endpoint')
            n=int(self.headers.get('Content-Length','0'))
            if not 0<n<=MAX_BYTES:raise ValueError('Invalid PDF size')
            pdf=self.rfile.read(n)
            if not pdf.startswith(b'%PDF-'):raise ValueError('Expected PDF')
            args=parse_qs(urlparse(self.path).query);ip=args.get('ip',[''])[0];path=args.get('path',['/ipp/print'])[0]
            status=print_ipp(ip,path,pdf)
            self.send_json(200,{'ok':True,'ipp_status':status})
        except Exception as exc:self.send_json(400,{'error':str(exc)})

if __name__=='__main__':
    print(f'Local IPP printing bridge: http://127.0.0.1:{PORT} — press Ctrl+C to stop')
    ThreadingHTTPServer(('127.0.0.1',PORT),Handler).serve_forever()
