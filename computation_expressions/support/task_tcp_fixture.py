"""Real loopback TCP fixture; verify the peer sees EOF on success/cancel/timeout."""
import argparse,os,socket,subprocess,threading,time
from pathlib import Path

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--daslang',required=True)
    parser.add_argument('--script',default=str(Path(__file__).resolve().parents[1]/'tests/test_task_tcp.das'))
    parser.add_argument('--jit',action='store_true')
    args=parser.parse_args()
    with socket.socket() as server:
        server.bind(('127.0.0.1',0));server.listen();server.settimeout(.1)
        lock=threading.Lock();stop=threading.Event();workers=[];counts={'accepted':0,'peer_eof':0,'server_eof':0};errors=[]
        def client(conn):
            try:
                with conn:
                    conn.settimeout(5)
                    data=b''
                    while not data.endswith(b'\n'):
                        part=conn.recv(128)
                        if not part: raise AssertionError('connection closed before request')
                        data+=part
                    if data==b'eof\n':
                        with lock: counts['server_eof']+=1
                        return
                    if data==b'ok\n':
                        conn.sendall(b'hel');time.sleep(.01);conn.sendall(b'lo\n')
                    elif data!=b'wait\n': raise AssertionError(f'bad request: {data!r}')
                    while conn.recv(128): pass
                    with lock: counts['peer_eof']+=1
            except Exception as e:
                with lock: errors.append(str(e))
        def accept():
            while not stop.is_set():
                try: conn,_=server.accept()
                except socket.timeout: continue
                with lock: counts['accepted']+=1
                worker=threading.Thread(target=client,args=(conn,),daemon=True);workers.append(worker);worker.start()
        thread=threading.Thread(target=accept,daemon=True);thread.start()
        command=[args.daslang,args.script,'-no-module-cache']
        if args.jit: command+=['-jit','-jit-no-cache']
        env=os.environ.copy();env['CE_TASK_TCP_PORT']=str(server.getsockname()[1])
        try:
            result=subprocess.run(command,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
            print(result.stdout,end='')
            if result.returncode: raise RuntimeError(f'daslang exited {result.returncode}')
            for worker in workers: worker.join(6)
            assert not errors,errors
            assert counts=={'accepted':4,'peer_eof':3,'server_eof':1},counts
            assert not any(w.is_alive() for w in workers),'open server connection'
            print(f'TCP peer closure verified: {counts}')
        finally:
            stop.set();thread.join(1)

if __name__=='__main__': main()
