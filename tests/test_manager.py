import base64
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit, unquote
import zipfile

ROOT=Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'Xray.sh').read_text()
HELPER=SOURCE.split("<<'PY'\n",1)[1].split('\nPY\n}',1)[0]
NS={'__name__':'test_helper'}
exec(HELPER,NS)
CORE=os.environ.get('XRAY_TEST_BINARY','')
KEY=base64.urlsafe_b64encode(bytes(range(32))).decode().rstrip('=')

class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        (self.root/'tmp').mkdir()
        self.code=SOURCE.rsplit('\nif [[',1)[0]
        self.prefix=f'''
BINARY='{self.root}/xray'
CONFIG_DIR='{self.root}/config'
CONFIG_FILE="$CONFIG_DIR/config.json"
CLIENT_FILE="$CONFIG_DIR/config.txt"
META_FILE="$CONFIG_DIR/client-meta.json"
ASSET_DIR='{self.root}/assets'
LOCK_FILE='{self.root}/manager.lock'
export TMPDIR='{self.root}/tmp'
'''
    def shell(self,code,data='',expected=0,timeout=8):
        result=subprocess.run(['bash','-c',self.code+self.prefix+code],
            input=data,text=True,capture_output=True,timeout=timeout)
        self.assertEqual(result.returncode,expected,result.stderr+result.stdout)
        return result
    def existing(self):
        (self.root/'config').mkdir(exist_ok=True)
        (self.root/'xray').write_text('original-binary')
        (self.root/'xray').chmod(0o755)
        (self.root/'config/config.json').write_text('{"existing": true}')
    def test_eof_exits_menu_and_continue(self):
        code='id() { echo 0; }; require_platform() { :; }; is_installed() { return 1; }; is_running() { return 1; }; main'
        for data in ('','invalid\n'):
            result=self.shell(code,data)
            self.assertEqual(result.stdout.count('=== Xray 管理工具 ==='),1)
    def test_install_preserves_existing_config(self):
        self.existing()
        result=self.shell('require_platform() { echo SHOULD_NOT_RUN; }; install_xray',expected=1)
        self.assertNotIn('SHOULD_NOT_RUN',result.stdout)
        self.assertEqual((self.root/'config/config.json').read_text(),'{"existing": true}')
    def test_download_and_validation_failure_preserve_files(self):
        self.existing()
        for failure in ('download','validation'):
            code='''
require_platform() { :; }; assert_service_layout() { :; }; install_dependencies() { :; }
download_core() { echo staged >"$1/xray"; }
validate_config() { return 1; }
systemctl() { echo SHOULD_NOT_RUN; }
'''
            if failure=='download': code+='\ndownload_core() { return 1; }\n'
            result=self.shell(code+'\nupdate_xray',expected=1)
            self.assertNotIn('SHOULD_NOT_RUN',result.stdout)
            self.assertEqual((self.root/'xray').read_text(),'original-binary')
            self.assertEqual((self.root/'config/config.json').read_text(),'{"existing": true}')
            self.assertFalse(list((self.root/'tmp').iterdir()))
    def test_atomic_write_failure_preserves_target_and_cleans_stage(self):
        target=self.root/'target'; target.write_text('old')
        source=self.root/'source'; source.write_text('new')
        for command in ('cat','chown','chmod','mv'):
            self.shell(f'{command}() {{ return 1; }}; atomic_write "{source}" "{target}" 600 root:root',expected=1)
            self.assertEqual(target.read_text(),'old')
            self.assertFalse(list(self.root.glob('target.tmp.*')))
    def test_configuration_permissions(self):
        self.existing()
        client=self.root/'config/config.txt'; client.write_text('secret')
        self.shell('SERVICE_GROUP=$(id -gn); secure_config')
        self.assertEqual((self.root/'config').stat().st_mode & 0o777,0o750)
        self.assertEqual((self.root/'config/config.json').stat().st_mode & 0o777,0o640)
        self.assertEqual(client.stat().st_mode & 0o777,0o600)
    def test_failed_restart_is_not_success(self):
        result=self.shell('assert_service_layout() { :; }; validate_config() { :; }; systemctl() { :; }; sleep() { :; }; is_running() { return 1; }; show_logs() { echo LOG_SHOWN; }; restart_service',expected=1)
        self.assertIn('LOG_SHOWN',result.stdout)
    def test_uninstall_defaults_to_cancel(self):
        for data in ('','\n','n\n'):
            result=self.shell('systemctl() { echo SHOULD_NOT_RUN; }; uninstall_xray',data)
            self.assertNotIn('SHOULD_NOT_RUN',result.stdout)
    def test_ip_validation_and_manual_fallback(self):
        result=self.shell("curl() { return 1; }; public_ip",'invalid\n2001:db8::1\n')
        self.assertEqual(result.stdout.strip(),'2001:db8::1')
        self.shell('curl() { return 1; }; public_ip','',expected=1)
    def test_dependency_install_does_not_upgrade_system(self):
        result=self.shell('command() { return 1; }; package_manager() { echo apt-get; }; apt-get() { echo "APT:$*"; }; install_dependencies')
        self.assertIn('APT:update',result.stdout)
        self.assertIn('APT:install',result.stdout)
        self.assertNotIn('upgrade',result.stdout)
    def test_rpm_dependencies_preserve_minimal_curl_and_coreutils(self):
        result=self.shell('command() { if [ "$2" = python3 ]; then return 1; fi; builtin command "$@"; }; package_manager() { echo dnf; }; dnf() { echo "DNF:$*"; }; install_dependencies')
        self.assertIn('DNF:install',result.stdout)
        self.assertNotIn(' coreutils',result.stdout)
        self.assertNotIn(' curl',result.stdout)
    def test_incompatible_service_layout_is_rejected(self):
        self.shell('systemctl() { echo "{ path=/opt/custom/xray ; argv[]=/opt/custom/xray run -confdir /etc/custom ; }"; }; assert_service_layout',expected=1)
        self.shell('systemctl() { echo "{ path=$BINARY ; argv[]=$BINARY run -config $CONFIG_FILE ; }"; }; assert_service_layout')
    def test_lock_blocks_concurrent_mutation(self):
        result=self.shell('exec 8>"$LOCK_FILE"; flock -n 8; locked echo SHOULD_NOT_RUN',expected=1)
        self.assertNotIn('SHOULD_NOT_RUN',result.stdout)
    def test_ctrl_c_in_logs_returns(self):
        executable=self.root/'journalctl'
        executable.write_text('#!/bin/sh\necho LOG_READY\nexec sleep 30\n')
        executable.chmod(0o755)
        runner=self.root/'runner'
        runner.write_text(self.code+self.prefix+f'\nexport PATH="{self.root}:$PATH"\nshow_logs follow\necho RETURNED_TO_MENU\n')
        pid,fd=pty.fork()
        if pid==0: os.execlp('bash','bash',str(runner))
        output=b''
        try:
            deadline=time.monotonic()+5
            while b'LOG_READY' not in output and time.monotonic()<deadline:
                if select.select([fd],[],[],.1)[0]: output+=os.read(fd,4096)
            self.assertIn(b'LOG_READY',output)
            os.write(fd,b'\x03')
            while b'RETURNED_TO_MENU' not in output and time.monotonic()<deadline:
                if select.select([fd],[],[],.1)[0]:
                    try: output+=os.read(fd,4096)
                    except OSError: break
            self.assertIn(b'RETURNED_TO_MENU',output)
        finally:
            try: os.killpg(pid,signal.SIGTERM)
            except ProcessLookupError: pass
            os.waitpid(pid,0); os.close(fd)

class HelperTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
    def test_key_formats_and_failure(self):
        for label in ('PublicKey','Public key','Password','Password (PublicKey)'):
            output='PrivateKey: '+KEY+'\n'+label+': '+KEY+'\n'
            with patch.object(NS['subprocess'],'run',return_value=subprocess.CompletedProcess([],0,output,'')):
                self.assertEqual(NS['keypair']('core')['public'],KEY)
        with patch.object(NS['subprocess'],'run',return_value=subprocess.CompletedProcess([],0,'PrivateKey: invalid','')):
            with self.assertRaises(ValueError): NS['keypair']('core')
    def test_json_comments_do_not_damage_urls(self):
        path=self.root/'config.json'
        path.write_text('{"url":"https://example.test/a//b",/* comment */"n":2 // comment\n}')
        self.assertEqual(NS['read_config'](path),{'url':'https://example.test/a//b','n':2})
    def test_recover_previous_ipv6_export(self):
        client=self.root/'config.txt'
        client.write_text('vless://id@2001:db8::1:443?type=tcp#HK\n')
        self.assertEqual(NS['existing_meta'](self.root/'missing',client),{'address':'2001:db8::1','name':'HK'})
    def test_checksum_prevents_extraction(self):
        archive=self.root/'core.zip'; digest=self.root/'core.zip.dgst'
        with zipfile.ZipFile(archive,'w') as z: z.writestr('xray',b'test-binary')
        digest.write_text('SHA2-256= '+'0'*64+'\n')
        with self.assertRaises(ValueError): NS['unpack'](archive,digest,self.root)
        self.assertFalse((self.root/'xray').exists())
        digest.write_text('SHA2-256= '+hashlib.sha256(archive.read_bytes()).hexdigest()+'\n')
        NS['unpack'](archive,digest,self.root)
        self.assertEqual((self.root/'xray').read_bytes(),b'test-binary')
    def test_export_reads_current_values_and_escapes_ipv6(self):
        config={'inbounds':[{'protocol':'vless','port':443,'tag':'xhttp','settings':{'clients':[{'id':'test-id'}]},
            'streamSettings':{'network':'xhttp','security':'reality','realitySettings':{'privateKey':KEY,'shortIds':['123abc'],'serverNames':['example.test']},
            'xhttpSettings':{'path':'/a b?c&d','host':'example.test','mode':'auto'}}}]}
        with patch.dict(NS,{'keypair':lambda *a: {'public':KEY}}):
            line=NS['export_clients'](config,{'address':'2001:db8::1','name':'HK # &'},'core').strip()
            parsed=urlsplit(line); query=parse_qs(parsed.query)
            self.assertEqual(parsed.hostname,'2001:db8::1')
            self.assertEqual(parsed.port,443)
            self.assertEqual(query['sid'],['123abc'])
            self.assertEqual(query['path'],['/a b?c&d'])
            self.assertNotIn('flow',query)
            config['inbounds'][0]['port']=444
            self.assertEqual(urlsplit(NS['export_clients'](config,{'address':'203.0.113.1'},'core').strip()).port,444)
    def test_add_ss_preserves_existing_inbounds_and_is_idempotent(self):
        config={'inbounds':[{'protocol':'vless','port':443,'settings':{'clients':[{'id':'keep'}]}}]}
        original=copy.deepcopy(config['inbounds'])
        NS['add_ss'](config)
        self.assertEqual(config['inbounds'][:1],original)
        once=copy.deepcopy(config)
        NS['add_ss'](config)
        self.assertEqual(config,once)
    def test_ss2022_export_round_trip_ipv6(self):
        config=NS['add_ss']({'inbounds':[]})
        config['inbounds'][0]['settings']['password']=base64.b64encode(bytes([251])*16).decode()
        uri=urlsplit(NS['export_clients'](config,{'address':'2001:db8::1','name':'US'},'unused').strip())
        self.assertEqual(uri.scheme,'ss')
        self.assertEqual(uri.hostname,'2001:db8::1')
        self.assertEqual(unquote(uri.username),'2022-blake3-aes-128-gcm')
        self.assertEqual(unquote(uri.password),config['inbounds'][0]['settings']['password'])
        self.assertEqual(uri.fragment,'US-ss2022')
    def test_new_config_has_distinct_ports_and_valid_identity(self):
        with patch.dict(NS,{'keypair':lambda *a: {'private':KEY}}):
            config=NS['new_config']('core')
        a,b,ss=config['inbounds']
        self.assertEqual(len({i['port'] for i in config['inbounds']}),3)
        self.assertEqual(len(base64.b64decode(ss['settings']['password'])),16)
        self.assertEqual(ss['settings']['network'],'tcp,udp')
        self.assertNotEqual(a['port'],b['port'])
        self.assertEqual(a['settings']['clients'][0]['flow'],'xtls-rprx-vision')
        self.assertEqual(b['settings']['clients'][0]['flow'],'')
        self.assertEqual(a['streamSettings']['realitySettings'],b['streamSettings']['realitySettings'])

if __name__=='__main__': unittest.main()

