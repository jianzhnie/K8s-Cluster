#!/usr/bin/env bash
set -euo pipefail

die() { echo "$*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "$1 未安装或不在 PATH 中"; }
need_file() { [[ -f "$1" ]] || die "$2: $1"; }

readonly INVENTORY="${INVENTORY:-hosts}"
readonly TARGET="${TARGET:-all}"
readonly SRC_TAR="${SRC_TAR:-/root/containerd/docker.tar}"
readonly DEST_TAR="${DEST_TAR:-/root/docker.tar}"
readonly EXTRACT_DIR="${EXTRACT_DIR:-/root}"
readonly DOCKER_DIR="${DOCKER_DIR:-/root/docker}"

need_cmd ansible
need_file "$INVENTORY" "inventory 文件不存在"
need_file "$SRC_TAR" "安装包不存在"

readonly -a ANSIBLE=(ansible -i "$INVENTORY" "$TARGET")

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/install_docker.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

remote_install="$tmp_dir/docker-install.sh"
cat >"$remote_install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

dest_tar="${1:?dest_tar required}"
extract_dir="${2:?extract_dir required}"
docker_dir="${3:?docker_dir required}"

mkdir -p "$extract_dir"
tar -xf "$dest_tar" -C "$extract_dir"

if [[ ! -d "$docker_dir" ]]; then
  echo "未找到目录: $docker_dir" >&2
  exit 1
fi

for f in docker dockerd docker-init docker-proxy docker.service; do
  if [[ ! -e "$docker_dir/$f" ]]; then
    echo "未找到文件: $docker_dir/$f" >&2
    exit 1
  fi
done

install -d -m 0755 /usr/local/bin /etc/docker /etc/systemd/system

install -m 0755 \
  "$docker_dir/docker" \
  "$docker_dir/dockerd" \
  "$docker_dir/docker-init" \
  "$docker_dir/docker-proxy" \
  /usr/local/bin/

install -m 0644 "$docker_dir/docker.service" /etc/systemd/system/docker.service

if [[ -f "$docker_dir/daemon.json" ]]; then
  install -m 0644 "$docker_dir/daemon.json" /etc/docker/daemon.json
fi

systemctl daemon-reload
systemctl enable --now docker
systemctl is-active --quiet docker
EOF
chmod +x "$remote_install"

"${ANSIBLE[@]}" -m copy -a "src=$SRC_TAR dest=$DEST_TAR owner=root group=root mode=0644"
"${ANSIBLE[@]}" -m script -a "$remote_install $DEST_TAR $EXTRACT_DIR $DOCKER_DIR"
