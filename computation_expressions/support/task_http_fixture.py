"""Local HTTP fixture for task_http tests: serves a few routes on 127.0.0.1."""
import argparse,os,subprocess,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def reply(self,status,body,headers=()):
        data=body.encode('utf-8')
        self.send_response(status)
        for key,value in headers:self.send_header(key,value)
        self.send_header('Content-Length',str(len(data)))
        self.end_headers()
        if self.command!='HEAD':self.wfile.write(data)
    def do_GET(self):
        if self.path=='/hello':self.reply(200,'hello',[('X-Fixture','yes'),('Content-Type','text/plain')])
        elif self.path=='/slow':time.sleep(1.5);self.reply(200,'slow')
        elif self.path=='/header':self.reply(200,self.headers.get('X-Token',''))
        else:self.reply(404,'missing')
    def do_POST(self):
        n=int(self.headers.get('Content-Length','0'))
        body=self.rfile.read(n).decode('utf-8')
        self.reply(201,body,[('Content-Type',self.headers.get('Content-Type',''))])

def main():
    ap=argparse.ArgumentParser()
    execution=ap.add_mutually_exclusive_group(required=True)
    execution.add_argument('--daslang');execution.add_argument('--aot-host')
    ap.add_argument('--sdk-root')
    ap.add_argument('--script',default=str(Path(__file__).resolve().parents[1]/'tests/test_task_http.das'))
    ap.add_argument('--jit',action='store_true');args=ap.parse_args()
    if args.aot_host and (not args.sdk_root or args.jit):ap.error('--aot-host requires --sdk-root and cannot use --jit')
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    env=dict(os.environ,CE_HTTP_PORT=str(server.server_address[1]))
    if args.aot_host:command=[args.aot_host,args.sdk_root,args.script]
    else:
        command=[args.daslang,args.script,'-no-module-cache']
        if args.jit:command+=['-jit','-jit-no-cache']
    try:code=subprocess.run(command,env=env,timeout=120).returncode
    finally:server.shutdown();server.server_close()
    raise SystemExit(code)

if __name__=='__main__':main()
