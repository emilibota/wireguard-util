#!/bin/sh
## Inspired by https://www.smarthomebeginner.com/linux-wireguard-vpn-server-setup/
set -eu

DIR="/etc/wireguard"
CONF_NAME="wg0"
DEFAULT_IP="10.8.0.1"
YES=0

usage() {
cat <<'EOF'
Usage:
  wg-util.sh [-y] [-c NAME] set-server [-p PORT] [-i IP] [-pv PRIVATE_KEY_FILE] [-pu PUBLIC_KEY_FILE] [-d DIR]
  wg-util.sh [-y] [-c NAME] get-port [-d DIR]
  wg-util.sh [-y] [-c NAME] get-ip [-d DIR]
  wg-util.sh [-y] [-c NAME] create-client CLIENT [-i IP] [--dns DNS] [-d DIR]
  wg-util.sh [-y] [-c NAME] remove-client CLIENT [-d DIR]
  wg-util.sh -h | --help

Global:
  -y                      install WireGuard without prompting
  -c, --conf-name NAME    WireGuard config/interface name; default wg0

set-server:
  -p, --port PORT
  -i, --ip IP             server IP without CIDR; default 10.8.0.1
  -pv, --private-key FILE private key file path
  -pu, --public-key FILE  public key file path
  -d, --directory DIR     default /etc/wireguard

create-client:
  -i, --ip IP             client IP without CIDR; auto if omitted
  --dns DNS               optional DNS in client config
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y) YES=1; shift ;;
    -c|--conf-name) CONF_NAME="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) break ;;
  esac
done

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 0; }
shift || true

cmd_exists() { command -v "$1" >/dev/null 2>&1; }
conf() { echo "$DIR/$CONF_NAME.conf"; }
strip_cidr() { echo "$1" | cut -d/ -f1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
}

install_wg() {
  cmd_exists wg && cmd_exists wg-quick && return

  echo "WireGuard is not installed."
  if [ "$YES" != 1 ]; then
    printf "Install WireGuard now? [y/N] "
    read ans
    case "$ans" in y|Y|yes|YES) ;; *) exit 1 ;; esac
  fi

  if cmd_exists apt-get; then apt-get update && apt-get install -y wireguard
  elif cmd_exists dnf; then dnf install -y wireguard-tools
  elif cmd_exists yum; then yum install -y wireguard-tools
  elif cmd_exists pacman; then pacman -Sy --noconfirm wireguard-tools
  elif cmd_exists apk; then apk add wireguard-tools
  else echo "Unsupported package manager." >&2; exit 1
  fi
}

parse_common() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -d|--directory) DIR="$2"; shift 2 ;;
      -c|--conf-name) CONF_NAME="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
}

random_port() {
  awk 'BEGIN{srand(); print int(49152+rand()*(65535-49152+1))}'
}

get_port_cmd() {
  parse_common "$@"
  awk -F= '/^[[:space:]]*ListenPort[[:space:]]*=/{gsub(/[ \t]/,"",$2); print $2; exit}' "$(conf)"
}

get_ip_cmd() {
  parse_common "$@"
  awk -F= '/^[[:space:]]*Address[[:space:]]*=/{gsub(/[ \t]/,"",$2); print $2; exit}' "$(conf)" | cut -d/ -f1
}

server_private_key() {
  awk -F= '/^[[:space:]]*PrivateKey[[:space:]]*=/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}' "$(conf)"
}

server_public_key() {
  server_private_key | wg pubkey
}

get_endpoint_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'
}

next_client_ip() {
  base="$(get_ip_cmd -d "$DIR" | awk -F. '{print $1"."$2"."$3"."}')"
  max=1

  nums=$(awk '
    /^[[:space:]]*AllowedIPs[[:space:]]*=/ {
      split($0,a,"=");
      gsub(/[ \t]/,"",a[2]);
      split(a[2],ips,",");
      for(i in ips) {
        split(ips[i],b,"/");
        split(b[1],o,".");
        if(o[4] ~ /^[0-9]+$/) print o[4];
      }
    }
  ' "$(conf)")

  for n in $nums; do [ "$n" -gt "$max" ] && max="$n"; done
  echo "${base}$((max + 1))"
}

sync_wg() {
  wg-quick down "$CONF_NAME" >/dev/null 2>&1 || true
  wg-quick up "$(conf)"
}

set_server() {
  need_root; install_wg

  PORT=""
  IP="$DEFAULT_IP"
  PRIV_FILE=""
  PUB_FILE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -p|--port) PORT="$2"; shift 2 ;;
      -i|--ip) IP="$(strip_cidr "$2")"; shift 2 ;;
      -pv|--private-key) PRIV_FILE="$2"; shift 2 ;;
      -pu|--public-key) PUB_FILE="$2"; shift 2 ;;
      -d|--directory) DIR="$2"; shift 2 ;;
      -c|--conf-name) CONF_NAME="$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  mkdir -p "$DIR"
  chmod 700 "$DIR"

  [ -n "$PORT" ] || PORT="$(random_port)"
  [ -n "$PRIV_FILE" ] || PRIV_FILE="$DIR/$CONF_NAME.key"
  [ -n "$PUB_FILE" ] || PUB_FILE="$DIR/$CONF_NAME.pub"

  if [ ! -f "$PRIV_FILE" ]; then
    wg genkey > "$PRIV_FILE"
    chmod 600 "$PRIV_FILE"
  fi

  wg pubkey < "$PRIV_FILE" > "$PUB_FILE"
  chmod 644 "$PUB_FILE"

  cat > "$(conf)" <<EOF
[Interface]
Address = $IP/24
ListenPort = $PORT
PrivateKey = $(cat "$PRIV_FILE")
SaveConfig = false
EOF

  chmod 600 "$(conf)"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
  sync_wg

  echo "Created $(conf)"
  echo "IP: $IP"
  echo "Port: $PORT"
}

create_client() {
  need_root; install_wg

  [ $# -ge 1 ] || { echo "Client name required." >&2; exit 1; }
  CLIENT="$1"; shift

  IP=""
  DNS=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -i|--ip) IP="$(strip_cidr "$2")"; shift 2 ;;
      --dns) DNS="$2"; shift 2 ;;
      -d|--directory) DIR="$2"; shift 2 ;;
      -c|--conf-name) CONF_NAME="$2"; shift 2 ;;
      *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
  done

  [ -f "$(conf)" ] || { echo "Run set-server first." >&2; exit 1; }
  grep -q "^# client:$CLIENT\$" "$(conf)" 2>/dev/null && { echo "Client exists." >&2; exit 1; }

  [ -n "$IP" ] || IP="$(next_client_ip)"

  if grep -q "AllowedIPs[[:space:]]*=[[:space:]]*$IP/32" "$(conf)"; then
    echo "IP already in use: $IP" >&2
    exit 1
  fi

  C_PRIV_FILE="$DIR/$CLIENT.key"
  C_PUB_FILE="$DIR/$CLIENT.pub"

  wg genkey > "$C_PRIV_FILE"
  chmod 600 "$C_PRIV_FILE"
  wg pubkey < "$C_PRIV_FILE" > "$C_PUB_FILE"
  chmod 644 "$C_PUB_FILE"

  C_PRIV="$(cat "$C_PRIV_FILE")"
  C_PUB="$(cat "$C_PUB_FILE")"
  S_PUB="$(server_public_key)"
  PORT="$(get_port_cmd -d "$DIR")"
  ENDPOINT="$(get_endpoint_ip)"
  [ -n "$ENDPOINT" ] || ENDPOINT="<SERVER_PUBLIC_IP>"

  cat >> "$(conf)" <<EOF

# client:$CLIENT
[Peer]
PublicKey = $C_PUB
AllowedIPs = $IP/32
EOF

  sync_wg

  cat <<EOF
Client config for $CLIENT:

[Interface]
PrivateKey = $C_PRIV
Address = $IP/32$( [ -n "$DNS" ] && printf '\nDNS = %s' "$DNS" )

[Peer]
PublicKey = $S_PUB
Endpoint = $ENDPOINT:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
}

remove_client() {
  need_root; install_wg

  [ $# -ge 1 ] || { echo "Client name required." >&2; exit 1; }
  CLIENT="$1"; shift
  parse_common "$@"

  awk -v target="# client:$CLIENT" '
    $0 == target { skip=1; next }
    skip && /^\[Peer\]/ { next }
    skip && /^#/ { skip=0 }
    skip && /^\[/ { skip=0 }
    !skip { print }
  ' "$(conf)" > "$(conf).tmp"

  mv "$(conf).tmp" "$(conf)"
  sync_wg
  echo "Removed client: $CLIENT"
}

case "$cmd" in
  set-server) set_server "$@" ;;
  get-port) get_port_cmd "$@" ;;
  get-ip) get_ip_cmd "$@" ;;
  create-client) create_client "$@" ;;
  remove-client) remove_client "$@" ;;
  -h|--help) usage ;;
  *) usage; exit 1 ;;
esac