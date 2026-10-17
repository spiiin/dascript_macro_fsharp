"""Local RFC6455 fixture: real handshakes, fragmented echo, and peer closure."""
import argparse,base64,hashlib,os,socket,struct,subprocess,tempfile,threading
from pathlib import Path

GUID=b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11'
def exact(conn,n):
    data=b''
    while len(data)<n:
        part=conn.recv(n-len(data))
        if not part:raise EOFError()
        data+=part
    return data

def frame(conn,opcode,payload=b'',fin=True):
    n=len(payload);head=bytes([(128 if fin else 0)|opcode])
    head+=bytes([n]) if n<126 else b'\x7e'+struct.pack('!H',n)
    conn.sendall(head+payload)

def read_frame(conn):
    a,b=exact(conn,2);n=b&127
    if n==126:n=struct.unpack('!H',exact(conn,2))[0]
    elif n==127:n=struct.unpack('!Q',exact(conn,8))[0]
    if n>1048576:raise AssertionError('oversized client frame')
    if not b&128:raise AssertionError('client frame must be masked')
    mask=exact(conn,4);data=exact(conn,n)
    return a&15,bytes(x^mask[i%4] for i,x in enumerate(data))

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--daslang',required=True)
    ap.add_argument('--script',default=str(Path(__file__).resolve().parents[1]/'tests/test_task_hv.das'))
    ap.add_argument('--jit',action='store_true');args=ap.parse_args()
    with tempfile.TemporaryDirectory(prefix='ce-hv-') as folder, socket.socket() as server:
        server.bind(('127.0.0.1',0));server.listen();server.settimeout(.1)
        stop=threading.Event();lock=threading.Lock();workers=[];errors=[]
        counts={'accepted':0,'closed':0,'pending_handshakes':0}
        def client(conn):
            path=None
            try:
                with conn:
                    conn.settimeout(8);request=b''
                    while not request.endswith(b'\r\n\r\n'):
                        request+=exact(conn,1)
                        if len(request)>8192:raise AssertionError('oversized handshake')
                    lines=request.decode('ascii').split('\r\n');path=lines[0].split()[1].strip('/')
                    headers=dict(line.split(':',1) for line in lines[1:] if ':' in line)
                    key=next(value.strip() for name,value in headers.items() if name.lower()=='sec-websocket-key')
                    Path(folder,path).touch()
                    if path.startswith('handshake_'):
                        with lock:counts['pending_handshakes']+=1
                        while conn.recv(4096):pass
                        return
                    accept=base64.b64encode(hashlib.sha1(key.encode()+GUID).digest())
                    conn.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n\r\n')
                    if path=='binary':frame(conn,2,b'abc')
                    elif path=='oversize':frame(conn,1,b'x'*128)
                    elif path=='peer_close':frame(conn,8,struct.pack('!H',1000))
                    while True:
                        opcode,data=read_frame(conn)
                        if opcode==8: return
                        if opcode==9:frame(conn,10,data);continue
                        if opcode!=1:raise AssertionError(f'unexpected opcode {opcode}')
                        Path(folder,'received_'+path).touch()
                        if path.startswith('pair_error_left_'):
                            # Do not fail the first request until the second is really active.
                            right='silent_pair_error_right_'+path.removeprefix('pair_error_left_')
                            for _ in range(5000):
                                if Path(folder,'received_'+right).exists():break
                                if stop.wait(.001):raise AssertionError('pair stopped before second request')
                            else:raise AssertionError('second request did not reach the server')
                            frame(conn,2,b'first request failure')
                        if path.startswith('echo') or path=='fault':
                            frame(conn,1,data[:2],False);frame(conn,0,data[2:])
            except (EOFError,ConnectionResetError,ConnectionAbortedError,BrokenPipeError):pass
            except Exception as exc:
                with lock:errors.append(str(exc))
            finally:
                with lock:counts['closed']+=1
                if path is not None:Path(folder,'closed_'+path).touch()
        def accept_loop():
            while not stop.is_set():
                try:conn,_=server.accept()
                except socket.timeout:continue
                with lock:counts['accepted']+=1
                worker=threading.Thread(target=client,args=(conn,),daemon=True);workers.append(worker);worker.start()
        thread=threading.Thread(target=accept_loop,daemon=True);thread.start()
        env=os.environ.copy();env['CE_HV_PORT']=str(server.getsockname()[1]);env['CE_HV_MARKERS']=folder.replace('\\','/')
        command=[args.daslang,args.script,'-no-module-cache']
        if args.jit:command+=['-jit','-jit-no-cache']
        try:
            result=subprocess.run(command,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
            print(result.stdout,end='')
            if result.returncode:raise RuntimeError(f'daslang exited {result.returncode}')
        finally:
            stop.set();thread.join(2)
            for worker in workers:worker.join(9)
        if Path(args.script).name=='test_task_hv.das':
            assert counts['pending_handshakes']==4,counts
        assert not errors,errors
        assert counts['accepted']==counts['closed'],counts
        assert not any(w.is_alive() for w in workers),'live server connection'
        print(f'WebSocket peer closure verified: {counts}')
if __name__=='__main__':main()
