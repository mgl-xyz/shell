#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_BASE_DIR="${SHELL_AUTOMATION_HOME:-/opt/shell-automation}"
NGINX_UI_DIR="${NGINX_UI_DIR:-$DEFAULT_BASE_DIR/nginx-ui}"
MGX_DIR="${MGX_DIR:-$DEFAULT_BASE_DIR/mgx}"
MGX_CONF_DIR="$MGX_DIR/data/mgx/conf.d/ssl-conf.d"
MGX_IMAGE="${MGX_IMAGE:-hotpot/mgx:ssl-ml}"
NGINX_UI_IMAGE="${NGINX_UI_IMAGE:-uozi/nginx-ui:latest}"
SCRIPT_UPDATE_URL="${SCRIPT_UPDATE_URL:-}"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[DONE]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
fatal() { printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || fatal "缺少命令：$1"; }
compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    printf 'docker compose'
  elif command -v docker-compose >/dev/null 2>&1; then
    printf 'docker-compose'
  else
    fatal "缺少 docker compose 插件或 docker-compose"
  fi
}
ensure_docker() {
  need_cmd docker
  docker info >/dev/null 2>&1 || fatal "Docker 未运行，或当前用户没有 Docker 权限"
  compose_cmd >/dev/null
}
ensure_dir() { mkdir -p "$1"; }

pause() { read -r -p '按回车继续...' _ || true; }
prompt_default() {
  local prompt="$1" default="$2" value
  read -r -p "$prompt [$default]: " value || true
  printf '%s' "${value:-$default}"
}
prompt_required() {
  local prompt="$1" value
  while true; do
    read -r -p "$prompt: " value || true
    [[ -n "$value" ]] && { printf '%s' "$value"; return; }
    warn "不能为空，请重新输入"
  done
}
confirm() {
  local prompt="$1" value
  read -r -p "$prompt [y/N]: " value || true
  [[ "$value" =~ ^[Yy]$ ]]
}
valid_domain() {
  [[ "$1" =~ ^(\*\.)?([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}
compose_file_exists() { [[ -f "$1/docker-compose.yml" ]]; }
run_compose() { local dir="$1"; shift; (cd "$dir" && $(compose_cmd) "$@"); }

show_container_status() {
  local name="$1"
  docker ps -a --filter "name=^/${name}$" --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
}

install_nginx_ui() {
  ensure_docker
  local http_port https_port data_dir compose_file
  http_port="$(prompt_default 'nginx-ui HTTP 管理端口' '8080')"
  https_port="$(prompt_default 'nginx-ui HTTPS 管理端口' '8443')"
  data_dir="$NGINX_UI_DIR/data"
  compose_file="$NGINX_UI_DIR/docker-compose.yml"
  ensure_dir "$data_dir"
  cat > "$compose_file" <<YAML
name: nginx-ui
services:
  nginx-ui:
    container_name: nginx-ui
    image: $NGINX_UI_IMAGE
    restart: always
    network_mode: bridge
    ports:
      - "$http_port:80"
      - "$https_port:443"
    volumes:
      - "$data_dir:/etc/nginx-ui"
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
YAML
  info "启动 nginx-ui：$compose_file"
  run_compose "$NGINX_UI_DIR" up -d
  success "nginx-ui 已安装/启动。访问：http://服务器IP:$http_port"
}

install_mgx() {
  ensure_docker
  local email compose_file
  email="$(prompt_default "Let's Encrypt 邮箱 CERTBOT_EMAIL" 'admin@example.com')"
  [[ "$email" == "admin@example.com" ]] && warn "建议改成真实邮箱，便于接收证书通知"
  ensure_dir "$MGX_CONF_DIR"
  compose_file="$MGX_DIR/docker-compose.yml"
  cat > "$compose_file" <<YAML
name: mgx
services:
  mgx:
    container_name: mgx
    image: $MGX_IMAGE
    restart: always
    environment:
      - CERTBOT_EMAIL=$email
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - mgx-data:/etc/letsencrypt
      - ./data/mgx/conf.d/ssl-conf.d:/ssl-conf.d
volumes:
  mgx-data:
YAML
  info "启动 mgx：$compose_file"
  run_compose "$MGX_DIR" up -d
  success "mgx 已安装/启动。配置目录：$MGX_CONF_DIR"
}

write_mgx_site_conf() {
  local domain="$1" upstream="$2" conf_file safe_name proxy_block
  valid_domain "$domain" || fatal "域名格式不正确：$domain"
  safe_name="${domain//\*/wildcard}"
  safe_name="${safe_name//[^A-Za-z0-9_.-]/_}"
  conf_file="$MGX_CONF_DIR/$safe_name.conf"
  ensure_dir "$MGX_CONF_DIR"
  if [[ -n "$upstream" ]]; then
    proxy_block="        include proxy.conf;\n        proxy_pass $upstream;"
  else
    proxy_block="        root html;\n        index index.html index.htm;"
  fi
  cat > "$conf_file" <<CONF
server {
    charset utf-8;
    server_name $domain;

    listen 443 ssl;
    http2 on;

    ssl_certificate     /etc/letsencrypt/live/$domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$domain/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$domain/chain.pem;
    ssl_session_timeout 5m;
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE:ECDH:AES:HIGH:!NULL:!aNULL:!MD5:!ADH:!RC4;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_prefer_server_ciphers on;
    ssl_dhparam /etc/letsencrypt/dhparams/dhparam.pem;

    error_page 500 502 503 504 404 403 /error.html;
    location = /error.html {
        root html;
    }

    location / {
$(printf '%b' "$proxy_block")
    }
}
CONF
  success "已生成站点配置：$conf_file"
}

add_mgx_site() {
  ensure_docker
  [[ -f "$MGX_DIR/docker-compose.yml" ]] || warn "未发现 mgx 安装记录；建议先在菜单中安装/启动 hotpot/mgx SSL"
  local domain upstream mode
  while true; do
    domain="$(prompt_required '请输入域名，例如 www.example.com')"
    valid_domain "$domain" && break
    warn "域名格式不正确：$domain"
  done
  cat <<MODE
请选择站点类型：
1) 反向代理到已有服务
2) 静态站点占位配置
MODE
  read -r -p '请选择 [1]: ' mode || true
  mode="${mode:-1}"
  if [[ "$mode" == "1" ]]; then
    upstream="$(prompt_required '请输入反代地址，例如 http://172.17.0.1:3000')"
  else
    upstream=""
  fi
  write_mgx_site_conf "$domain" "$upstream"
  if [[ -f "$MGX_DIR/docker-compose.yml" ]]; then
    run_compose "$MGX_DIR" up -d
    docker exec mgx nginx -s reload || warn "容器重载失败，请查看：docker logs -f mgx"
  fi
}

download_file() {
  local url="$1" output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$output" "$url"
  else
    fatal "缺少 curl 或 wget，无法下载脚本"
  fi
}

upgrade_self() {
  if [[ -d "$REPO_ROOT/.git" ]]; then
    need_cmd git
    info "检测到 Git 仓库，使用 git 升级：$REPO_ROOT"
    (cd "$REPO_ROOT" && git fetch --all --prune && git pull --ff-only)
    success "脚本已升级到当前分支最新版本"
    return
  fi

  [[ -n "$SCRIPT_UPDATE_URL" ]] || fatal "当前不是 Git 仓库。请设置 SCRIPT_UPDATE_URL 为脚本 raw 下载地址后再升级，例如：SCRIPT_UPDATE_URL=https://raw.githubusercontent.com/<owner>/<repo>/<branch>/scripts/nginx_tools.sh bash $SCRIPT_NAME"
  local current_script tmp_file
  current_script="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  tmp_file="$(mktemp)"
  info "从远程下载最新脚本：$SCRIPT_UPDATE_URL"
  download_file "$SCRIPT_UPDATE_URL" "$tmp_file"
  bash -n "$tmp_file"
  cat "$tmp_file" > "$current_script"
  chmod +x "$current_script"
  rm -f "$tmp_file"
  success "脚本已升级：$current_script"
}

manage_service() {
  ensure_docker
  local title="$1" dir="$2" container="$3" image="$4" choice
  while true; do
    cat <<MENU

$title 管理
安装目录：$dir
镜像：$image
1) 查看容器状态
2) 启动/重新创建容器
3) 停止容器
4) 重启容器
5) 查看日志
6) 拉取/升级镜像并重启
7) 删除容器（保留数据和 compose 文件）
8) 删除本地镜像
9) 返回主菜单
MENU
    read -r -p '请选择: ' choice || true
    case "$choice" in
      1) show_container_status "$container"; pause ;;
      2)
        compose_file_exists "$dir" || { warn "未安装，请先从主菜单安装 $title"; pause; continue; }
        run_compose "$dir" up -d; pause ;;
      3)
        compose_file_exists "$dir" && run_compose "$dir" stop || docker stop "$container" || true
        pause ;;
      4)
        compose_file_exists "$dir" && run_compose "$dir" restart || docker restart "$container"
        pause ;;
      5)
        docker logs --tail=200 -f "$container" ;;
      6)
        compose_file_exists "$dir" || { warn "未安装，请先从主菜单安装 $title"; pause; continue; }
        run_compose "$dir" pull
        run_compose "$dir" up -d
        pause ;;
      7)
        confirm "确认删除容器 $container？" && { compose_file_exists "$dir" && run_compose "$dir" rm -sf || docker rm -f "$container" || true; }
        pause ;;
      8)
        confirm "确认删除本地镜像 $image？" && docker image rm "$image" || true
        pause ;;
      9|0) return ;;
      *) warn "未知选项：$choice"; pause ;;
    esac
  done
}

main_menu() {
  local choice
  while true; do
    cat <<MENU

$SCRIPT_NAME - Docker/Nginx 自动化菜单
1) 安装/启动 nginx-ui
2) 管理已安装 nginx-ui 容器/镜像
3) 安装/启动 hotpot/mgx SSL
4) 管理已安装 hotpot/mgx 容器/镜像
5) 为 mgx 按步骤添加域名站点配置
6) 升级本仓库脚本
0) 退出
MENU
    read -r -p '请选择: ' choice || true
    case "$choice" in
      1) install_nginx_ui; pause ;;
      2) manage_service 'nginx-ui' "$NGINX_UI_DIR" 'nginx-ui' "$NGINX_UI_IMAGE" ;;
      3) install_mgx; pause ;;
      4) manage_service 'hotpot/mgx SSL' "$MGX_DIR" 'mgx' "$MGX_IMAGE" ;;
      5) add_mgx_site; pause ;;
      6) upgrade_self; pause ;;
      0) exit 0 ;;
      *) warn "未知选项：$choice"; pause ;;
    esac
  done
}

usage() {
  cat <<USAGE
用法：
  bash $SCRIPT_NAME

说明：
  本脚本采用菜单选择方式。运行后选择安装、管理容器/镜像、添加 mgx 域名站点或升级自身脚本。
USAGE
}

main() {
  case "${1:-}" in
    -h|--help|help) usage ;;
    "") main_menu ;;
    *) usage; fatal "不再通过命令行一次性录入参数，请直接运行 bash $SCRIPT_NAME 后按菜单选择" ;;
  esac
}

main "$@"
