# RockType 官网

域名确定为 **https://type.roarkist.com/**。纯静态 HTML / CSS / 原生 JavaScript，无构建步骤、运行依赖、CDN、外部字体或追踪脚本。

## 文件与预览

- `index.html`：产品首页。
- `privacy/index.html`、`releases/index.html`、`404.html`：隐私、开发进展与未找到页面。
- `style.css`：1120px / 12 列布局、系统深浅色、360px 起的响应式布局与减少动态效果。
- `site.js`：移动导航、滚动进入、可暂停的九条波形；页面内容不依赖 JavaScript。
- `no-script.css`：无 JavaScript 时展开移动导航。
- `assets/`：真实产品离屏渲染图、应用图标与 1200×630 OG 图片。每张小于 300KB。
- `robots.txt`、`sitemap.xml`：搜索发现。
- `deploy/`：[Rocky Linux 9 / nginx / certbot 运维说明](deploy/README.md)与本站 HTTP bootstrap vhost。

在仓库根目录运行：

```sh
python3 -m http.server 8018 --bind 127.0.0.1 --directory website
```

访问 `http://127.0.0.1:8018/`。纯文件打开不支持以 `/` 开头的站内资源路径；需要通过 HTTP 预览。Python 预览服务器不会套用 nginx 的自定义 404；可直接访问 `/404.html` 检查页面。

下载统一指向 `https://github.com/Roarkai/RockType/releases/latest`，**待发布确认**。更新日志将开发进展与正式发行分开，不虚构版本号、安装包或发布日期。页脚“版本与下载”以 Releases 为准。

## 图片来源与边界

所有产品界面由真实 AppKit / SwiftUI 视图离屏渲染；文字、画布与配置仅使用专门编写的展示内容，不读取用户桌面、录音、剪贴板或密钥。模型名展示可配置能力，不代表调用过该服务。

| 资源 | 来源 |
| --- | --- |
| `candidate-*.webp` | `Tests/InputMethodTests/PanelChecks.swift` 可选官网分支，真实 `SquirrelPanel` |
| `candidate-translation-*.webp` | 同一隔离测试中的真实 `RoarkTTranslationPanel` |
| `translate-*.webp` | `W1WebsiteRenderingTests.swift`，真实 `TranslateWindowController` / 视图 |
| `selection-*.webp` | 同一渲染入口，真实 `LiveSelectionToolbar` |
| `voice-*.webp` | 同一渲染入口，真实 `RoarkTVoiceHUDContent` |
| `screenshot-*.webp` | 同一渲染入口，真实 `CaptureCanvas` / 工具栏，展示画布不来自用户桌面 |
| `models-*.webp` | 同一渲染入口，真实 `OperationModelSettings` |
| `icon.png` | R7 编译后的 App 图标 Default 128@2x 离屏导出 |
| `og.png` | 本次新作：原生产品图、品牌图标与系统字体在浏览器 Canvas 中合成后压缩 |

复现原生产品图：

```sh
ROARKT_WEBSITE_RENDER_DIR="$PWD/.build/w1/product" \
  swift test --filter 'websiteProductRenders|InputMethodChecks'
```

SwiftUI/AppKit 图进入指定目录；GPL 输入法隔离测试将候选/译文图写到 `.build/ime-evidence/`。输入法源代码没有链接进 MIT App 或官网运行时。网页使用压缩后的图，不依赖 `.build/`。

文案没有将受控评测的首字延迟与 OCR 分数当作用户速度/精度承诺；明确了 Apple 离线翻译的 macOS 26 / 语言包要求、语音模型下载、可选 AI 润色、密码输入保护和图片发送确认（可记住选择）。

## 部署与待确认项

`scripts/deploy-website.sh --check` 仅本地校验打包，不联系服务器。实际部署凭据由操作者以 `DEPLOY_HOST` / `DEPLOY_KEY` 提供；本任务没有执行 SSH、安装 nginx、申请证书或发布。

站点内容使用 `/var/www/rocktype/releases/<时间戳>` 与 `current` 软链；仅建立 `/etc/nginx/conf.d/type.roarkist.com.conf`，certbot 通过 `--nginx` 管理证书。正常更新保留其修改过的配置。详细首次发布、共享服务器保护与回滚见 `deploy/README.md`。

待操作者确认：

- GitHub 仓库、Releases 和实际安装包公开可用；签名/公证/版本信息以正式发布产物验收为准。
- Rocky Linux 9 的包源、SSH/sudo、域名、nginx vhost、SELinux 文件标签与 HTTP/HTTPS、证书签发续期和回滚。
- Lighthouse 尚未运行，不宣称达到 95 分；VoiceOver、Safari 与真实移动设备待人工验证。
- 本机 ego 的 `Page.captureScreenshot` 持续超时。`.build/w1/` 提供 1440 / 390 深浅色及 360 深色的浏览器 screen-media PDF 和栅格 PNG 预览；它们不是原生截图，打印路径的阴影/合成可能有差异。交互和自动无障碍检查在正常 DOM 页面中进行。原生截图待补。

完整检查与限制见 [018-W1 验收证据](../specs/evidence/018-W1.md)。
