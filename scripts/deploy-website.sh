#!/usr/bin/env bash
# Publish static content only. Never uploads packages, edits global nginx, or runs certbot.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mode=deploy
case "${1:-}" in
  --check) mode=check ;;
  --bootstrap-nginx) mode=bootstrap ;;
  --help|-h)
    printf '%s\n' 'Usage: scripts/deploy-website.sh [--check|--bootstrap-nginx]' \
      'Default: publish through the existing certbot-managed site, then verify HTTPS locally.' \
      '--check: validate/package locally; never connect to a server.' \
      '--bootstrap-nginx: install the HTTP vhost ONLY if its target file is absent.' \
      'Deployment requires DEPLOY_HOST=user@host and DEPLOY_KEY=/path/to/private-key.'
    exit 0 ;;
  '') ;;
  *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Only one option is accepted.' >&2; exit 2; }
site="$root/website"
payload=(index.html style.css site.js no-script.css 404.html robots.txt sitemap.xml assets privacy releases)
for item in "${payload[@]}"; do [[ -e "$site/$item" ]] || { echo "Missing website/$item" >&2; exit 1; }; done
[[ -s "$site/assets/og.png" && -s "$site/assets/icon.png" ]]
[[ -z "$(find "$site" -type l -print -quit)" ]] || { echo 'Website symlinks are not supported.' >&2; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/rocktype-website.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
COPYFILE_DISABLE=1 tar -czf "$work/site.tgz" -C "$site" "${payload[@]}"
if [[ "$mode" == check ]]; then
  printf 'Local package valid: %s bytes. No server contacted.\n' "$(wc -c < "$work/site.tgz" | tr -d ' ')"
  exit 0
fi
: "${DEPLOY_HOST:?Set DEPLOY_HOST=user@host}"
: "${DEPLOY_KEY:?Set DEPLOY_KEY to an existing local SSH private key}"
[[ -f "$DEPLOY_KEY" ]]
[[ "$DEPLOY_HOST" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.@:-]*$ && "$DEPLOY_HOST" != -* ]] || { echo 'Invalid SSH destination.' >&2; exit 2; }
release=$(date -u +%Y%m%dT%H%M%SZ)
digest=$(shasum -a 256 "$work/site.tgz" | awk '{print $1}')
ssh_args=(-i "$DEPLOY_KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=yes)
upload=$(ssh "${ssh_args[@]}" "$DEPLOY_HOST" 'mktemp -d /tmp/rocktype-upload.XXXXXXXX')
[[ "$upload" =~ ^/tmp/rocktype-upload\.[a-zA-Z0-9]{8}$ ]] || { echo 'Unexpected upload directory.' >&2; exit 1; }
# The upload directory is private to this invocation. Remote cleanup also runs after rollback.
cleanup_upload() {
  ssh "${ssh_args[@]}" "$DEPLOY_HOST" "rm -rf -- '$upload'" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup_upload EXIT
scp "${ssh_args[@]}" "$work/site.tgz" "$site/deploy/nginx.conf" "$DEPLOY_HOST:$upload/"
ssh "${ssh_args[@]}" "$DEPLOY_HOST" "if [ \"\$(id -u)\" -eq 0 ]; then exec bash -s -- '$release' '$digest' '$upload' '$mode'; else exec sudo -n bash -s -- '$release' '$digest' '$upload' '$mode'; fi" <<'REMOTE'
set -euo pipefail
release=$1; digest=$2; upload=$3; mode=$4
[[ "$release" =~ ^[0-9]{8}T[0-9]{6}Z$ && "$digest" =~ ^[0-9a-f]{64}$ ]]
[[ "$upload" =~ ^/tmp/rocktype-upload\.[a-zA-Z0-9]{8}$ ]]
[[ "$mode" == bootstrap || "$mode" == deploy ]]
root=/var/www/rocktype
config=/etc/nginx/conf.d/type.roarkist.com.conf
exec 9>/var/lock/rocktype-website.lock
flock -n 9 || { echo 'Another RockType deployment is active.' >&2; exit 1; }
for command in nginx curl restorecon sha256sum systemctl; do command -v "$command" >/dev/null; done
nginx -t
systemctl is-active --quiet nginx
if [[ "$mode" == bootstrap ]]; then
  [[ ! -e "$config" && ! -L "$config" ]] || { echo 'Site config already exists; preserve certbot changes and use normal deployment.' >&2; exit 1; }
  # Never introduce a duplicate server_name already declared by another config.
  active_config=$(nginx -T 2>&1)
  if grep -Eq '^[[:space:]]*server_name[[:space:]][^;]*type[.]roarkist[.]com([[:space:];]|$)' <<< "$active_config"; then
    echo 'Domain already exists in nginx; reconcile its dedicated vhost manually.' >&2; exit 1
  fi
else
  [[ -f "$config" && ! -L "$config" ]]
  grep -Eq '^[[:space:]]*server_name[[:space:]]+type[.]roarkist[.]com[[:space:]]*;' "$config"
  grep -Eq '^[[:space:]]*root[[:space:]]+/var/www/rocktype/current[[:space:]]*;' "$config" || { echo 'Site root must be /var/www/rocktype/current.' >&2; exit 1; }
fi
[[ ! -e "$root/current" || -L "$root/current" ]] || { echo 'current must be a symlink, never a directory.' >&2; exit 1; }
[[ ! -e "$root/releases/$release" ]]
printf '%s  %s\n' "$digest" "$upload/site.tgz" | sha256sum -c -
[[ ! -L "$root" && ! -L "$root/releases" ]]
install -d -m 755 "$root" "$root/releases"
mkdir "$root/releases/$release"
tar -xzf "$upload/site.tgz" -C "$root/releases/$release" --no-same-owner
printf '%s\n' "$release" > "$root/releases/$release/site-release.txt"
find "$root/releases/$release" -type d -exec chmod 755 {} +
find "$root/releases/$release" -type f -exec chmod 644 {} +
restorecon -RF "$root"
previous=$(readlink "$root/current" || true)
switched=0; installed=0
rollback() {
  trap - ERR INT TERM
  set +e
  recovery_failed=0
  if [[ "$switched" == 1 ]]; then
    if [[ -n "$previous" ]]; then
      if ! { ln -s "$previous" "$root/.restore-$release" && mv -Tf "$root/.restore-$release" "$root/current"; }; then recovery_failed=1; fi
    else
      rm -f "$root/current" || recovery_failed=1
    fi
  fi
  if [[ "$installed" == 1 ]]; then
    if ! { rm -f "$config" && nginx -t && systemctl reload nginx; }; then recovery_failed=1; fi
  fi
  if [[ "$recovery_failed" == 1 ]]; then
    echo "Deployment failed; rollback needs operator attention. Previous current: ${previous:-none}" >&2
  else
    echo "Deployment failed. Previous current/config restored." >&2
  fi
  echo "Failed release retained: $root/releases/$release" >&2
  exit 1
}
trap rollback ERR INT TERM
if [[ "$mode" == bootstrap ]]; then
  installed=1
  install -m 644 "$upload/nginx.conf" "$config"
  restorecon "$config"
fi
nginx -t
ln -s "$root/releases/$release" "$root/.next-$release"
switched=1
mv -Tf "$root/.next-$release" "$root/current"
if [[ "$mode" == bootstrap ]]; then systemctl reload nginx; fi
if [[ "$mode" == bootstrap ]]; then
  actual=$(curl --fail --silent --show-error --noproxy '*' --max-time 15 -H 'Host: type.roarkist.com' http://127.0.0.1/site-release.txt)
else
  actual=$(curl --fail --silent --show-error --noproxy '*' --max-time 15 --resolve type.roarkist.com:443:127.0.0.1 https://type.roarkist.com/site-release.txt)
fi
[[ "$actual" == "$release" ]]
trap - ERR INT TERM
printf 'Published %s. Previous current: %s\n' "$release" "${previous:-none}"
printf 'Retained releases: %s/releases (no automatic pruning).\n' "$root"
REMOTE
