import copy
import http.server
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from urllib.parse import parse_qs, urlsplit
from test_manager import NS, CORE

def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1',0))
        return sock.getsockname()[1]

class Origin(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'xray-manager-proxy-ok'
        self.send_response(200); self.send_header('Content-Length',str(len(body))); self.end_headers()
        self.wfile.write(body)
    def log_message(self,*args): pass

@unittest.skipUnless(CORE and Path(CORE).is_file(),'XRAY_TEST_BINARY is required')
class TrafficTests(unittest.TestCase):
    def test_exported_tcp_and_xhttp_links_reach_origin(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); processes=[]; logs=[]
            origin=http.server.ThreadingHTTPServer(('127.0.0.1',0),Origin)
            threading.Thread(target=origin.serve_forever,daemon=True).start()
            def launch(args,name):
                log=open(root/(name+'.log'),'w+'); logs.append(log)
                process=subprocess.Popen(args,stdout=log,stderr=log)
                processes.append(process)
                return process
            def wait_port(port,process):
                deadline=time.monotonic()+10
                while time.monotonic()<deadline:
                    if process.poll() is not None: raise AssertionError('Process exited: '+str(process.returncode))
                    try:
                        with socket.create_connection(('127.0.0.1',port),timeout=.2): return
                    except OSError: time.sleep(.05)
                raise AssertionError('Listener did not become ready')
            try:
                subprocess.run(['openssl','req','-x509','-newkey','ec','-pkeyopt','ec_paramgen_curve:prime256v1',
                    '-nodes','-keyout',str(root/'key.pem'),'-out',str(root/'cert.pem'),'-days','1',
                    '-subj','/CN=example.test','-addext','subjectAltName=DNS:example.test'],check=True,capture_output=True)
                tls_port=free_port()
                tls=launch(['openssl','s_server','-accept','127.0.0.1:'+str(tls_port),
                    '-cert',str(root/'cert.pem'),'-key',str(root/'key.pem'),'-tls1_3','-alpn','h2','-www'],'target')
                wait_port(tls_port,tls)
                config=NS['new_config'](CORE)
                for inbound in config['inbounds']:
                    inbound['listen']='127.0.0.1'
                    reality=inbound['streamSettings']['realitySettings']
                    reality['target']='127.0.0.1:'+str(tls_port)
                    reality['serverNames']=['example.test']
                server_file=root/'server.json'; server_file.write_text(json.dumps(config))
                subprocess.run([CORE,'run','-test','-config',str(server_file)],check=True,capture_output=True)
                exported=NS['export_clients'](config,{'address':'127.0.0.1','name':'CI'},CORE)
                server=launch([CORE,'run','-config',str(server_file)],'server')
                for inbound in config['inbounds']: wait_port(inbound['port'],server)
                for line in exported.splitlines():
                    if not line: continue
                    uri=urlsplit(line); query={k:v[0] for k,v in parse_qs(uri.query,keep_blank_values=True).items()}
                    with self.subTest(network=query['type']):
                        proxy_port=free_port()
                        stream={'network':query['type'],'security':'reality','realitySettings':{
                            'serverName':query['sni'],'fingerprint':query['fp'],
                            'publicKey':query['pbk'],'shortId':query['sid']}}
                        if query['type']=='xhttp':
                            stream['xhttpSettings']={'path':query['path'],'mode':query['mode']}
                        client={'log':{'loglevel':'warning'},'inbounds':[{'listen':'127.0.0.1','port':proxy_port,
                            'protocol':'socks','settings':{'auth':'noauth','udp':False}}],
                            'outbounds':[{'protocol':'vless','settings':{'vnext':[{'address':uri.hostname,
                            'port':uri.port,'users':[{'id':uri.username,'encryption':'none','flow':query.get('flow','')}]}]},
                            'streamSettings':stream}]}
                        client_file=root/('client-'+query['type']+'.json'); client_file.write_text(json.dumps(client))
                        subprocess.run([CORE,'run','-test','-config',str(client_file)],check=True,capture_output=True)
                        process=launch([CORE,'run','-config',str(client_file)],'client-'+query['type'])
                        wait_port(proxy_port,process)
                        result=subprocess.run(['curl','--fail','--silent','--show-error','--max-time','12',
                            '--noproxy','','--proxy','socks5h://127.0.0.1:'+str(proxy_port),
                            'http://127.0.0.1:'+str(origin.server_port)+'/probe'],
                            capture_output=True,text=True,timeout=15)
                        self.assertEqual(result.returncode,0,result.stderr)
                        self.assertEqual(result.stdout,'xray-manager-proxy-ok')
                        process.terminate(); process.wait(timeout=5)
            except Exception:
                for log in logs:
                    log.flush(); log.seek(0)
                    print(log.name+':\n'+log.read()[-6000:])
                raise
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                        try: process.wait(timeout=5)
                        except subprocess.TimeoutExpired: process.kill(); process.wait()
                origin.shutdown(); origin.server_close()
                for log in logs: log.close()

if __name__=='__main__': unittest.main()
