# Rocky Linux 9 / nginx / certbot

本站独占的路径：

- 内容：`/var/www/rocktype/releases/<UTC 时间戳>`，`/var/www/rocktype/current` 原子软链。
- vhost：`/etc/nginx/conf.d/type.roarkist.com.conf`。
- 日志：`/var/log/nginx/rocktype.{access,error}.log`。

这是共享服务器。不要替换 `/etc/nginx/nginx.conf`、删除默认站点、改其他 vhost、关闭 SELinux 或重启整台服务器。脚本不执行包安装、DNS、防火墙或证书操作，不删除旧 release，不上传安装包。

## 操作者准备（本任务未执行）

1. 确认域名 A/AAAA 指向目标服务器，80/443 可访问；检查现有 nginx `server_name`，防止重复域名。已有该域名时，保留 certbot 的 TLS/重定向段，仅由操作者将站点的 `root` 调整为 `/var/www/rocktype/current`。脚本拒绝覆盖已有 vhost。
2. Rocky Linux 9 安装 nginx、EPEL 中的 certbot 与 python3-certbot-nginx、policycoreutils-python-utils，以及 curl、tar、util-linux。由管理员按服务器现有包源管理，确认 nginx 正在运行。
3. 保持 SELinux Enforcing。默认 `/var/www` 通常已有 `httpd_sys_content_t` 映射；先用 `matchpathcon /var/www/rocktype` 检查。若无映射，管理员执行 `semanage fcontext -a -t httpd_sys_content_t '/var/www/rocktype(/.*)?'`，已有自定义规则时由管理员检查后调整，随后 `restorecon -RF /var/www/rocktype`。脚本每次恢复本站标签，不改变全局布尔项。
4. 操作者建立 SSH known_hosts 信任，并提供 `DEPLOY_HOST=user@host`、`DEPLOY_KEY=/path/to/private-key`。远端用户须为 root，或可无交互执行 sudo bash。脚本不跳过主机身份检查、不接受密码交互、不回显私钥内容。

## 首次建立站点

```sh
# 仓库根目录：只校验本地包，不连接远端。
scripts/deploy-website.sh --check

# 操作者显式提供凭据后执行。只在 vhost 文件不存在时建立 HTTP 站点。
scripts/deploy-website.sh --bootstrap-nginx

# 在服务器上，由操作者交给 certbot 的 nginx 插件申请并管理证书。
sudo certbot --nginx -d type.roarkist.com --redirect
sudo nginx -t
sudo certbot renew --dry-run
```

联系邮箱、服务条款、续期 timer 和端口开放由操作者按既有运维流程处理。确认 certbot 的续期任务已启用。不得另外安装覆盖 nginx 的全局续期脚本。HTTP 模板不预填证书路径，避免证书尚不存在时导致整个共享 nginx 校验失败。HTTPS 完成后可在本站 TLS server 中添加 HSTS；不对其他域名或子域名强加策略。

## 后续更新与回滚

```sh
scripts/deploy-website.sh
```

正常更新只上传显式列出的静态文件，保留 certbot 修改过的 vhost。脚本对本站加锁、验证包 SHA-256、检查 `nginx -t`，再原子切换 `current`；正常内容更新无需 reload。首次安装 vhost 才在校验成功后 `systemctl reload nginx`。

切换后用域名与本机回环地址检查实际 release：正常更新验证 HTTPS 证书及 `site-release.txt`；bootstrap 检查 HTTP。失败会恢复旧软链；bootstrap 新建配置也撤回并校验/reload。失败的 release 保留供排查。脚本打印旧软链目标，操作者可据此手工 `ln -s <旧 release> <临时软链>`，再 `mv -Tf <临时软链> /var/www/rocktype/current`；先确认目标属于预期站点并存在。不要删除当前或准备回滚的 release。

本地只验证了脚本语法、打包和模板；Rocky Linux、SELinux、SSH/sudo、共享 nginx、certbot 签发/续期与远端回滚必须由操作者实际验收。
