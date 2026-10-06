#!/usr/bin/env bash
# Xray management for systemd and OpenRC hosts. Temporary files are staging files, not backups.
BINARY=/usr/local/bin/xray
CONFIG_DIR=/usr/local/etc/xray
CONFIG_FILE="$CONFIG_DIR/config.json"
CLIENT_FILE="$CONFIG_DIR/config.txt"
META_FILE="$CONFIG_DIR/client-meta.json"
ASSET_DIR=/usr/local/share/xray
UNIT_FILE=/etc/systemd/system/xray.service
LOCK_FILE=/run/lock/xray-manager.lock
SERVICE=xray
INIT_SYSTEM=systemd
OPENRC_FILE=/etc/init.d/xray
OPENRC_CONF=/etc/conf.d/xray
LOG_FILE=/var/log/xray/xray.log
OS_RELEASE=/etc/os-release

fail() { printf '错误: %s\n' "$*" >&2; return 1; }
is_installed() { [ -e "$BINARY" ] || [ -e "$CONFIG_FILE" ]; }
is_running() { service_action running; }
service_action() {
    local action=$1
    if [ "$INIT_SYSTEM" = openrc ]; then
        case "$action" in
            running|status) rc-service "$SERVICE" status;;
            enable) rc-update add "$SERVICE" default;;
            disable) rc-update del "$SERVICE" default;;
            reload) return 0;;
            exists) [ -e "$OPENRC_FILE" ];;
            *) rc-service "$SERVICE" "$action";;
        esac
    else
        case "$action" in
            running) systemctl is-active --quiet "$SERVICE";;
            status) systemctl status "$SERVICE" --no-pager -l;;
            exists) systemctl cat "$SERVICE" >/dev/null 2>&1;;
            reload) systemctl daemon-reload;;
            *) systemctl "$action" "$SERVICE";;
        esac
    fi
}
select_init() {
    if command -v systemctl >/dev/null && [ -d /run/systemd/system ]; then
        INIT_SYSTEM=systemd
    elif command -v rc-service >/dev/null && command -v rc-update >/dev/null && [ -d /run/openrc ]; then
        INIT_SYSTEM=openrc
        UNIT_FILE=$OPENRC_FILE
    else
        fail "需要正在运行的 systemd 或 OpenRC（不支持未启动 init 的普通容器）"
    fi
}
fetch() { curl -fLsS --retry 2 --connect-timeout 8 --max-time 180 "$@"; }

package_manager() {
    local ID
    [ -r "$OS_RELEASE" ] || return 1
    . "$OS_RELEASE"
    case "$ID" in
        alpine) echo apk;;
        debian|ubuntu) echo apt-get;;
        fedora|rhel|centos|rocky|almalinux|ol|amzn)
            if command -v dnf >/dev/null; then echo dnf
            elif command -v yum >/dev/null; then echo yum
            else return 1; fi;;
        *) fail "当前支持 Alpine、Debian/Ubuntu 和 RHEL/Fedora 系系统";;
    esac
}
require_platform() {
    package_manager >/dev/null || return 1
    select_init
}
install_dependencies() {
    local manager command missing=false
    for command in curl python3 flock useradd install mktemp nologin; do
        command -v "$command" >/dev/null || missing=true
    done
    if [ "$missing" = false ] && { [ -s /etc/ssl/certs/ca-certificates.crt ] || [ -s /etc/pki/tls/certs/ca-bundle.crt ]; }; then
        return 0
    fi
    manager=$(package_manager) || return 1
    if [ "$manager" = apt-get ]; then
        apt-get update &&
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            curl python3 ca-certificates coreutils util-linux passwd
    elif [ "$manager" = apk ]; then
        apk add --no-cache bash curl python3 ca-certificates coreutils util-linux shadow || return 1
    else
        local packages=(python3 ca-certificates util-linux shadow-utils)
        command -v curl >/dev/null || packages+=(curl)
        if ! command -v install >/dev/null || ! command -v mktemp >/dev/null; then
            packages+=(coreutils)
        fi
        "$manager" install -y "${packages[@]}"
    fi
}
architecture() {
    case "$(uname -m)" in
        x86_64|amd64) echo 64;;
        aarch64|arm64) echo arm64-v8a;;
        *) fail "当前支持 AMD64 / ARM64";;
    esac
}
atomic_write() {
    local source=$1 target=$2 mode=$3 owner=$4 temporary
    [ ! -L "$target" ] || { fail "拒绝替换符号链接: $target"; return 1; }
    temporary=$(mktemp "$target.tmp.XXXXXX") || return 1
    if cat "$source" >"$temporary" && chown "$owner" "$temporary" &&
       chmod "$mode" "$temporary" && mv -f -- "$temporary" "$target"; then
        return 0
    fi
    rm -f -- "$temporary"
    fail "写入失败: $target"
}
config_tool() {
    python3 - "$@" <<'PY'
import base64, hashlib, ipaddress, json, os, re, secrets, socket, subprocess, sys, uuid, zipfile
from pathlib import Path
from urllib.parse import quote, urlencode, urlsplit, unquote

def read_config(path):
    text = Path(path).read_text()
    # Xray accepts JSON comments. Remove only comments outside string literals.
    pattern = r'"(?:\\.|[^"\\])*"|//[^\r\n]*|/\*[\s\S]*?\*/'
    text = re.sub(pattern, lambda m: m[0] if m[0].startswith('"') else ' ', text)
    return json.loads(text)

def keypair(core, private=None):
    cmd = [core, 'x25519'] + (['-i', private] if private else [])
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    values = {}
    for line in result.stdout.splitlines():
        name, sep, value = line.partition(':')
        name = re.sub(r'[^a-z]', '', name.lower())
        if sep and name in ('privatekey', 'publickey', 'password', 'passwordpublickey'):
            value = value.strip()
            if not re.fullmatch(r'[A-Za-z0-9_-]{43}', value) or len(base64.urlsafe_b64decode(value+'=')) != 32:
                raise ValueError('内核输出了无效的 X25519 密钥')
            values['private' if name == 'privatekey' else 'public'] = value
    if 'public' not in values or (not private and 'private' not in values):
        raise ValueError('无法解析 X25519 密钥输出')
    return values

def new_config(core):
    private = keypair(core)['private']
    identity, sid, path = str(uuid.uuid4()), secrets.token_hex(8), '/'+secrets.token_hex(8)
    listeners, ports = [], []
    try:
        for _ in range(2):
            for attempt in range(128):
                sock = socket.socket()
                port = secrets.randbelow(55000)+10000
                try:
                    sock.bind(('0.0.0.0', port))
                except OSError:
                    sock.close()
                    continue
                listeners.append(sock); ports.append(port); break
            else:
                raise ValueError('无法找到可用端口')
        inbounds = []
        for network, port in zip(('tcp', 'xhttp'), ports):
            stream = {'network':network,'security':'reality','realitySettings':{
                'target':'www.ua.edu:443','serverNames':['www.ua.edu'],
                'privateKey':private,'shortIds':[sid]}}
            if network == 'xhttp':
                stream['xhttpSettings'] = {'path':path,'mode':'auto'}
            inbounds.append({'listen':'0.0.0.0','port':port,'tag':'vless-'+network,
                'protocol':'vless','settings':{'clients':[{'id':identity,
                'flow':'xtls-rprx-vision' if network == 'tcp' else ''}],'decryption':'none'},
                'streamSettings':stream})
        return add_ss({'log':{'loglevel':'warning'},'inbounds':inbounds,
                'outbounds':[{'protocol':'freedom','tag':'direct'},{'protocol':'blackhole','tag':'block'}]})
    finally:
        for sock in listeners: sock.close()

def add_ss(config):
    inbounds = config.setdefault('inbounds', [])
    if any(item.get('protocol') == 'shadowsocks' for item in inbounds):
        return config
    used = {str(item.get('port')) for item in inbounds}
    for _ in range(128):
        port = secrets.randbelow(55000) + 10000
        if str(port) in used: continue
        with socket.socket() as tcp, socket.socket(type=socket.SOCK_DGRAM) as udp:
            try:
                tcp.bind(('0.0.0.0', port)); udp.bind(('0.0.0.0', port))
            except OSError:
                continue
            inbounds.append({'listen':'0.0.0.0','port':port,'tag':'ss2022',
                'protocol':'shadowsocks','settings':{'method':'2022-blake3-aes-128-gcm',
                'password':base64.b64encode(secrets.token_bytes(16)).decode(),
                'network':'tcp,udp'}})
            return config
    raise ValueError('无法找到可用的 SS2022 TCP/UDP 端口')

def valid_ip(value):
    return str(ipaddress.ip_address(value.strip()))

def region_name(path, address):
    data = json.loads(Path(path).read_text())
    if data.get('success') is not True or valid_ip(data.get('ip', '')) != valid_ip(address):
        raise ValueError('IP 地区查询失败')
    code = data.get('country_code')
    if not isinstance(code, str) or not re.fullmatch(r'[A-Za-z]{2}', code):
        raise ValueError('IP 国家/地区代码无效')
    return code.upper()


def existing_meta(meta_path, client_path):
    if Path(meta_path).is_file():
        meta = json.loads(Path(meta_path).read_text())
        meta['address'] = valid_ip(meta['address'])
        return meta
    if Path(client_path).is_file():
        for line in Path(client_path).read_text().splitlines():
            if not line.startswith('vless://'): continue
            # Recover the previous export, including its unbracketed IPv6 bug.
            authority = line.split('@',1)[1].split('?',1)[0]
            host = authority.rsplit(':',1)[0].strip('[]')
            try:
                return {'address':valid_ip(host),'name':unquote(line.partition('#')[2]).strip() or 'Xray'}
            except ValueError:
                continue
    return {}

def export_clients(config, meta, core):
    host = valid_ip(meta['address'])
    authority = '['+host+']' if ':' in host else host
    name = str(meta.get('name','Xray')).strip() or 'Xray'
    if len(name)>80 or any(ord(c)<32 for c in name):
        raise ValueError('节点名称不能包含控制字符，且不能超过 80 字符')
    lines, public_keys = [], {}
    for item in config.get('inbounds',[]):
        if item.get('protocol') == 'shadowsocks':
            settings = item['settings']
            method, password = settings['method'], settings['password']
            if method != '2022-blake3-aes-128-gcm' or settings.get('users'):
                raise ValueError('当前 SS 导出只支持单用户 SS2022 AES-128-GCM')
            if len(base64.b64decode(password, validate=True)) != 16:
                raise ValueError('SS2022 AES-128 密钥必须为 16 字节')
            port = int(item['port'])
            if not 1 <= port <= 65535: raise ValueError('监听端口无效')
            label = name+'-'+item.get('tag','ss2022')
            lines.append('ss://'+quote(method,safe='')+':'+quote(password,safe='')
                         +'@'+authority+':'+str(port)+'#'+quote(label,safe=''))
            continue
        if item.get('protocol') != 'vless': continue
        stream = item.get('streamSettings',{})
        network = stream.get('network','tcp')
        if stream.get('security') != 'reality' or network not in ('tcp','raw','xhttp'):
            raise ValueError('当前导出只支持 TCP / XHTTP + REALITY 的 VLESS 入站')
        port = int(item['port'])
        if not 1 <= port <= 65535: raise ValueError('监听端口无效')
        reality = stream['realitySettings']
        private = reality['privateKey']
        if private not in public_keys: public_keys[private] = keypair(core,private)['public']
        short_ids = reality.get('shortIds',[''])
        sid = short_ids if isinstance(short_ids,str) else (short_ids[0] if short_ids else '')
        if not re.fullmatch(r'(?:[0-9a-fA-F]{2}){0,8}',sid):
            raise ValueError('REALITY short-id 格式无效')
        sni = reality['serverNames'][0]
        for index, user in enumerate(item['settings']['clients'],1):
            query = {'encryption':'none','security':'reality','sni':sni,'fp':'chrome',
                     'pbk':public_keys[private],'sid':sid,'type':'tcp' if network=='raw' else network}
            if user.get('flow'): query['flow']=user['flow']
            if network == 'xhttp':
                settings=stream.get('xhttpSettings',{})
                query.update(path=settings.get('path','/'),mode=settings.get('mode','auto'))
                if settings.get('host'): query['host']=settings['host']
                if settings.get('extra'): query['extra']=json.dumps(settings['extra'],separators=(',',':'))
            else:
                query['headerType']='none'
            tag = item.get('tag','vless-'+network)
            label = name+'-'+tag+(('-'+str(index)) if len(item['settings']['clients'])>1 else '')
            lines.append('vless://'+quote(str(user['id']),safe='')+'@'+authority+':'+str(port)
                         +'?'+urlencode(query,quote_via=quote)+'#'+quote(label,safe=''))
    if not lines: raise ValueError('没有可导出的 VLESS + REALITY 或 SS2022 入站')
    return '\n\n'.join(lines)+'\n'

def unpack(archive, digest_file, directory):
    matches = re.findall(r'(?im)^.*(?:SHA2?-?256|SHA256)[^=\r\n]*=\s*([0-9a-f]{64})\s*$',Path(digest_file).read_text())
    if len(matches)!=1 or hashlib.sha256(Path(archive).read_bytes()).hexdigest()!=matches[0].lower():
        raise ValueError('下载文件 SHA256 校验失败')
    with zipfile.ZipFile(archive) as z:
        for name in ('xray','geoip.dat','geosite.dat'):
            try: data=z.read(name)
            except KeyError:
                if name=='xray': raise ValueError('压缩包中缺少 Xray')
                continue
            output=Path(directory)/name
            output.write_bytes(data); output.chmod(0o755 if name=='xray' else 0o644)

def main():
    action, args=sys.argv[1],sys.argv[2:]
    if action=='new': print(json.dumps(new_config(args[0]),indent=2))
    elif action=='clients':
        print(export_clients(read_config(args[0]),json.loads(Path(args[1]).read_text()),args[2]),end='')
    elif action=='meta': print(json.dumps({'address':valid_ip(args[0]),'name':args[1]},ensure_ascii=False))
    elif action=='existing-meta': print(json.dumps(existing_meta(*args)))
    elif action=='get': print(json.loads(Path(args[0]).read_text()).get(args[1],''))
    elif action=='ip': print(valid_ip(args[0]))
    elif action=='region': print(region_name(*args))
    elif action=='unpack': unpack(*args)
    elif action=='version':
        value=json.loads(Path(args[0]).read_text())['tag_name']
        if not re.fullmatch(r'v\d+\.\d+\.\d+',value): raise ValueError('版本号格式无效')
        print(value)
    else: raise ValueError('未知配置操作')

if __name__=='__main__':
    try: main()
    except Exception as error:
        print('错误: '+('Xray 密钥生成失败' if isinstance(error, subprocess.CalledProcessError) else str(error)),file=sys.stderr)
        sys.exit(1)
PY
}
download_core() {
    local stage=$1 arch version url
    arch=$(architecture) || return 1
    fetch https://api.github.com/repos/XTLS/Xray-core/releases/latest -o "$stage/release.json" || return 1
    version=$(config_tool version "$stage/release.json") || return 1
    url="https://github.com/XTLS/Xray-core/releases/download/$version/Xray-linux-$arch.zip"
    printf '下载 Xray %s (%s)\n' "$version" "$arch"
    fetch "$url" -o "$stage/core.zip" &&
        fetch "$url.dgst" -o "$stage/core.zip.dgst" &&
        config_tool unpack "$stage/core.zip" "$stage/core.zip.dgst" "$stage" &&
        "$stage/xray" version
}
validate_config() {
    local core=$1 config=$2 assets=${3:-$ASSET_DIR}
    env XRAY_LOCATION_ASSET="$assets" "$core" run -test -config "$config"
}
assert_service_layout() {
    if [ "$INIT_SYSTEM" = openrc ]; then
        # Accept only this manager's generated service; conf.d overrides may alter its identity or command.
        [ ! -s "$OPENRC_CONF" ] && [ ! -L "$OPENRC_FILE" ] &&
            cmp -s "$OPENRC_FILE" <(SERVICE_USER=xray SERVICE_GROUP=$(id -gn xray) create_service /dev/stdout) || {
            fail "OpenRC 服务与本脚本模板不一致，或存在 conf.d 覆盖，停止操作"; return 1;
        }
        return 0
    fi
    local command
    command=$(systemctl show "$SERVICE" -p ExecStart --value) || return 1
    if [[ "$command" != *"$BINARY "* || "$command" != *"$CONFIG_FILE "* || "$command" == *"-confdir"* ]]; then
        fail "服务未使用本脚本的单文件配置，停止操作；请检查 systemctl cat xray"
        return 1
    fi
}
service_identity() {
    if [ "$INIT_SYSTEM" = openrc ]; then
        SERVICE_USER=xray
        SERVICE_GROUP=$(id -gn "$SERVICE_USER") || return 1
        return 0
    fi
    SERVICE_USER=$(systemctl show "$SERVICE" -p User --value) || return 1
    SERVICE_USER=${SERVICE_USER:-root}
    SERVICE_GROUP=$(systemctl show "$SERVICE" -p Group --value) || return 1
    [ -n "$SERVICE_GROUP" ] || SERVICE_GROUP=$(id -gn "$SERVICE_USER") || return 1
    id "$SERVICE_USER" >/dev/null || return 1
}
secure_config() {
    [ ! -L "$CONFIG_DIR" ] && [ ! -L "$CONFIG_FILE" ] || { fail "配置路径不能是符号链接"; return 1; }
    chown "root:$SERVICE_GROUP" "$CONFIG_DIR" && chmod 750 "$CONFIG_DIR" &&
        chown "root:$SERVICE_GROUP" "$CONFIG_FILE" && chmod 640 "$CONFIG_FILE" || return 1
    local file
    for file in "$CLIENT_FILE" "$META_FILE"; do
        if [ -e "$file" ]; then
            [ ! -L "$file" ] && chown root:root "$file" && chmod 600 "$file" || return 1
        fi
    done
}
public_ip() {
    local address url family
    for url in https://checkip.amazonaws.com https://ipv4.icanhazip.com https://api64.ipify.org; do
        family=--ipv4
        [ "$url" != https://api64.ipify.org ] || family=--ipv6
        if address=$(curl -fLsS "$family" --connect-timeout 4 --max-time 10 "$url") &&
           config_tool ip "$address" 2>/dev/null; then return 0; fi
    done
    while read -r -p '请输入服务器公网 IP（留空取消）: ' address; do
        [ -n "$address" ] || return 1
        config_tool ip "$address" 2>/dev/null && return 0
        printf 'IP 地址无效，请重试。\n' >&2
    done
    return 1
}
prepare_clients() {
    local config=$1 core=$2 stage=$3 address name region
    config_tool existing-meta "$META_FILE" "$CLIENT_FILE" >"$stage/previous.json" || return 1
    address=$(config_tool get "$stage/previous.json" address) || return 1
    name=$(config_tool get "$stage/previous.json" name) || return 1
    if [ -z "$address" ]; then address=$(public_ip) || return 1; fi
    if curl -fLsS --connect-timeout 4 --max-time 10 \
        "https://ipwho.is/$address?fields=success,ip,country_code" \
        -o "$stage/region.json" 2>/dev/null &&
        region=$(config_tool region "$stage/region.json" "$address" 2>/dev/null); then
        name=$region
    else
        name=${name:-$address}
        printf 'IP 地区查询失败，使用节点名称前缀: %s\n' "$name" >&2
    fi
    config_tool meta "$address" "$name" >"$stage/meta.json" &&
        config_tool clients "$config" "$stage/meta.json" "$core" >"$stage/client.txt"
}
write_clients() {
    atomic_write "$1/meta.json" "$META_FILE" 600 root:root &&
        atomic_write "$1/client.txt" "$CLIENT_FILE" 600 root:root
}
show_logs() {
    if [ "${1:-}" = follow ]; then
        trap ':' INT
        if [ "$INIT_SYSTEM" = openrc ]; then tail -n 30 -F "$LOG_FILE"
        else journalctl -u "$SERVICE" -f -n 30; fi
        trap 'exit 130' INT
        return 0
    fi
    if [ "$INIT_SYSTEM" = openrc ]; then
        [ -f "$LOG_FILE" ] && tail -n 30 "$LOG_FILE"
    else journalctl -u "$SERVICE" -n 30 --no-pager; fi
}
restart_service() {
    assert_service_layout && validate_config "$BINARY" "$CONFIG_FILE" || return 1
    if [ "$INIT_SYSTEM" = openrc ] && ! is_running >/dev/null 2>&1; then
        service_action start || return 1
    else service_action restart || return 1; fi
    sleep 2
    if ! is_running >/dev/null 2>&1; then
        show_logs
        fail "服务未保持运行，请检查日志"
        return 1
    fi
}
create_service() {
    local file=$1
    if [ "$INIT_SYSTEM" = openrc ]; then
        cat >"$file" <<EOF
#!/sbin/openrc-run
# Managed by Xray.sh
name="Xray"
description="Xray proxy service"
supervisor="supervise-daemon"
command="$BINARY"
command_args="run -config $CONFIG_FILE"
command_user="$SERVICE_USER:$SERVICE_GROUP"
pidfile="/run/xray.pid"
respawn_delay=3
respawn_max=0
capabilities="cap_net_bind_service+eip"
no_new_privs="yes"
output_log="$LOG_FILE"
error_log="$LOG_FILE"
export XRAY_LOCATION_ASSET="$ASSET_DIR"
depend() {
    need net
    after firewall
}
start_pre() {
    checkpath --directory --mode 0750 --owner "$SERVICE_USER:$SERVICE_GROUP" "${LOG_FILE%/*}" || return 1
    checkpath --file --mode 0640 --owner "$SERVICE_USER:$SERVICE_GROUP" "$LOG_FILE" || return 1
    "\$command" run -test -config "$CONFIG_FILE"
}
EOF
        return $?
    fi
    cat >"$file" <<EOF
[Unit]
Description=Xray proxy service
After=network-online.target
Wants=network-online.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_GROUP
Environment=XRAY_LOCATION_ASSET=$ASSET_DIR
ExecStart=$BINARY run -config $CONFIG_FILE
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
LimitNOFILE=1048576
Restart=on-failure
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}
install_xray() (
    if is_installed || service_action exists; then
        fail "检测到已有 Xray 或配置，请选择 9 更新；安装不会覆盖已有配置"
        return 1
    fi
    require_platform && install_dependencies || return 1
    umask 077
    local stage
    stage=$(mktemp -d) || return 1
    trap 'rm -rf -- "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    download_core "$stage" || return 1
    config_tool new "$stage/xray" >"$stage/config.json" &&
        validate_config "$stage/xray" "$stage/config.json" "$stage" &&
        prepare_clients "$stage/config.json" "$stage/xray" "$stage" || return 1
    if ! id xray >/dev/null 2>&1; then
        local nologin
        nologin=$(command -v nologin) || { fail "缺少 nologin"; return 1; }
        useradd --system --user-group --no-create-home --shell "$nologin" xray || return 1
    fi
    [ "$(id -u xray)" != 0 ] || { fail "xray 服务账号不能是 root"; return 1; }
    SERVICE_USER=xray
    SERVICE_GROUP=$(id -gn xray) || return 1
    install -d -m 755 /usr/local/bin "$ASSET_DIR" || return 1
    install -d -m 750 -o root -g "$SERVICE_GROUP" "$CONFIG_DIR" || return 1
    local data
    for data in geoip.dat geosite.dat; do
        if [ -f "$stage/$data" ] && [ ! -e "$ASSET_DIR/$data" ]; then
            atomic_write "$stage/$data" "$ASSET_DIR/$data" 644 root:root || return 1
        fi
    done
    local unit_mode=644
    [ "$INIT_SYSTEM" != openrc ] || unit_mode=755
    atomic_write "$stage/config.json" "$CONFIG_FILE" 640 "root:$SERVICE_GROUP" &&
        write_clients "$stage" &&
        atomic_write "$stage/xray" "$BINARY" 755 root:root &&
        create_service "$stage/xray.service" &&
        atomic_write "$stage/xray.service" "$UNIT_FILE" "$unit_mode" root:root || return 1
    service_action reload && service_action enable && restart_service || return 1
    printf 'Xray 安装完成\n'
    cat "$CLIENT_FILE"
)
update_xray() (
    [ -x "$BINARY" ] && [ -f "$CONFIG_FILE" ] || { fail "未找到完整安装"; return 1; }
    require_platform && assert_service_layout && install_dependencies || return 1
    umask 077
    local stage
    stage=$(mktemp -d) || return 1
    trap 'rm -rf -- "$stage"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    download_core "$stage" &&
        validate_config "$stage/xray" "$CONFIG_FILE" &&
        prepare_clients "$CONFIG_FILE" "$stage/xray" "$stage" &&
        service_identity && secure_config || return 1
    atomic_write "$stage/xray" "$BINARY" 755 root:root || return 1
    restart_service || { fail "内核已替换，但重启失败；请查看日志。未创建备份。"; return 1; }
    write_clients "$stage" || return 1
    printf 'Xray 更新完成\n'
    cat "$CLIENT_FILE"
)
refresh_clients() (
    [ -x "$BINARY" ] && [ -f "$CONFIG_FILE" ] || { fail "Xray 尚未安装"; return 1; }
    require_platform && assert_service_layout && install_dependencies || return 1
    umask 077
    local stage
    stage=$(mktemp -d) || return 1
    trap 'rm -rf -- "$stage"' EXIT
    validate_config "$BINARY" "$CONFIG_FILE" &&
        prepare_clients "$CONFIG_FILE" "$BINARY" "$stage" &&
        service_identity && secure_config && write_clients "$stage" || return 1
    cat "$CLIENT_FILE"
)
uninstall_xray() {
    local answer
    read -r -p '确认卸载 Xray 并删除配置？[y/N]: ' answer || return 0
    [[ "$answer" = y || "$answer" = Y ]] || return 0
    require_platform && assert_service_layout || return 1
    if is_running >/dev/null 2>&1; then service_action stop || return 1; fi
    service_action disable || return 1
    rm -f -- "$BINARY" "$UNIT_FILE" || return 1
    rm -rf -- "$CONFIG_DIR" || return 1
    if [ "$INIT_SYSTEM" = systemd ]; then
        rm -f -- /etc/systemd/system/xray@.service || return 1
        rm -rf -- /etc/systemd/system/xray.service.d /etc/systemd/system/xray@.service.d || return 1
    fi
    service_action reload || return 1
    printf 'Xray 已卸载\n'
}
locked() (
    command -v flock >/dev/null || { fail "缺少 flock，请安装 util-linux"; return 1; }
    mkdir -p -- "${LOCK_FILE%/*}" || return 1
    exec 9>"$LOCK_FILE" || return 1
    flock -n 9 || { fail "已有 Xray 管理操作正在运行"; return 1; }
    "$@"
)
show_menu() {
    local installed=false running=false
    is_installed && installed=true
    is_running >/dev/null 2>&1 && running=true
    [ ! -t 1 ] || clear
    printf '=== Xray 管理工具 ===\n'
    if "$installed"; then echo '安装状态: 已安装'; else echo '安装状态: 未安装'; fi
    if "$running"; then echo '运行状态: 已运行'; else echo '运行状态: 未运行'; fi
    printf '\n'
    printf '%s\n' '1. 安装 Xray 服务' '2. 卸载 Xray 服务'
    if "$installed"; then
        printf '%s\n' '3. 启动 Xray 服务' '4. 停止 Xray 服务' '5. 重启 Xray 服务' \
            '6. 检查 Xray 状态' '7. 查看 Xray 日志' '8. 查看 Xray 配置' '9. 更新 Xray 内核'
    fi
    printf '%s\n' '0. 退出' '====================='
    read -r -p '请输入选项编号: ' choice
}
main() {
    [ "$(id -u)" = 0 ] || { fail "请使用 root 运行"; return 1; }
    require_platform || return 1
    if ! command -v flock >/dev/null; then install_dependencies || return 1; fi
    trap 'exit 130' INT
    if [ "${1:-}" = --install ]; then locked install_xray; return $?; fi
    [ "$#" = 0 ] || { fail "未知参数"; return 1; }
    while show_menu; do
        case "$choice" in
            1) locked install_xray;;
            2) locked uninstall_xray;;
            3|5) locked restart_service;;
            4) locked service_action stop;;
            6) service_action status;;
            7) show_logs follow;;
            8) locked refresh_clients;;
            9) locked update_xray;;
            0) return 0;;
            *) echo '无效选项';;
        esac
        [ "$?" = 0 ] || printf '操作未完成，请检查上方错误信息。\n' >&2
        read -r -p '按 Enter 键继续...' || return 0
    done
    return 0
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi

