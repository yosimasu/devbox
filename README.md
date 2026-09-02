# devbox

一個 devcontainer **base image**，內含 [mise](https://mise.jdx.dev/) + [Claude Code](https://docs.anthropic.com/en/docs/claude-code)。
下游專案 `FROM` 它，再用 mise 依 `mise.toml` 預裝 node / python 等 runtime。

```
ghcr.io/yosimasu/devbox:latest       # 多架構：linux/amd64 + linux/arm64
ghcr.io/yosimasu/devbox:2026.9.0     # 版本 tag == 裡面 mise 的版本
```

## 設計

| 元件 | 怎麼裝 | 為什麼 |
|------|--------|--------|
| **mise** | 系統層 `/usr/local/bin/mise`，**pin 版本**、**shims 模式** | 版本鎖定 → build 可重現；shims dir 掛在 `PATH`，讓 build 期的 `RUN` 與非互動 shell 都能用 mise 裝的工具；互動 shell 另用 `mise activate` |
| **Claude Code** | 官方 native installer，裝在 `~/.local/bin` | **不依賴 node**，語言版本完全交給下游用 mise 決定 |
| base OS | `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | 內建非 root 的 `vscode` user、sudo、常用工具 |

Claude 的登入憑證**刻意不烤進 image**（屬個人資料）。容器內第一次跑 `claude` 時登入，或帶 `ANTHROPIC_API_KEY`。

## 版本策略

- **mise 版本 pin 在 `Dockerfile` 的 `ARG MISE_VERSION`**（單一版本來源）。本機與 CI build 都吃這個預設值，build 可重現。冒煙測試會斷言實際裝到的版本吻合 pin。
- **image 版本 tag 直接對齊 mise 版本**：CI 從 `Dockerfile` 讀出 pin，打成 `:<mise 版本>`（例：`:2026.9.0`）+ `:latest` + `:sha-xxxxxxx`。所以 image 版本一看就知道裡面 mise 是哪版。
- **升版 mise**：改 `Dockerfile` 裡 `ARG MISE_VERSION=vX.Y.Z` 這一行 → push 到 `main` → CI 自動 build 並打上新版本 tag。
- 每週定期 build 會跟上 **base OS / Claude Code** 的更新；**mise 維持 pin**，不會自己跳版。

## 下游怎麼用

複製 `example/` 那組結構到你的專案：

```
your-project/
├── mise.toml                     # 這個專案要的 runtime，跟 code 一起版控
└── .devcontainer/
    ├── Dockerfile
    └── devcontainer.json
```

```toml
# mise.toml
[tools]
node = "20"
python = "3.12"
```

```dockerfile
# .devcontainer/Dockerfile
FROM ghcr.io/yosimasu/devbox:latest    # 想鎖版就用 :2026.9.0
COPY mise.toml .
RUN mise trust && mise install
```

```jsonc
// .devcontainer/devcontainer.json
{
  "name": "your-project",
  "build": { "dockerfile": "Dockerfile", "context": ".." }
}
```

> `context: ".."` 是為了讓 `COPY mise.toml .` 抓得到專案根的 `mise.toml`。

## 本機驗證

```bash
# build base
docker build -t devbox:local .

# 跑起來確認
docker run --rm devbox:local bash -lc 'mise --version && claude --version'
```

不開 VS Code 測整套 devcontainer：`npm i -g @devcontainers/cli`，再 `devcontainer build --workspace-folder .`。

## CI / 發布

`.github/workflows/build-base.yml`：push 到 `main` 且改到 `Dockerfile` 時自動 build & push，另有 `workflow_dispatch`（手動）與每週定期重 build。

**各架構在原生 runner build**（amd64 → `ubuntu-latest`、arm64 → `ubuntu-24.04-arm`），push by digest，再 `docker buildx imagetools create` 合成多架構 manifest。用內建 `GITHUB_TOKEN` 推 GHCR，不需要自己的 PAT。arm64 原生 runner 靠 repo 為 **public** 而免費。

驗證發布的 manifest：

```bash
docker buildx imagetools inspect ghcr.io/yosimasu/devbox:latest
```

## 兩個踩過的坑

做「容器裡烤 Claude Code」都會遇到，記錄於此：

1. **`claude.ai/install.sh` 從 CI IP 會回 HTTP 403**（Cloudflare 擋資料中心 IP）。
   別用 `curl -fsSL … | bash` —— pipe 的 exit code 是 bash 的，curl 的 403 會被**默默吞掉**，後面變成 `claude: not found`（exit 127）。
   解法：下載到檔 + 帶瀏覽器 **User-Agent** + `--retry`，實測能繞過、失敗也會大聲報。見 `Dockerfile` 內的安裝步驟。

2. **Claude native binary 是 Bun 打包，x86-64 需要 AVX**。
   QEMU 模擬的 amd64 沒有 AVX → Bun segfault（在 arm64 機器上 `docker buildx --platform linux/amd64` 就會炸）。真實 amd64 硬體沒問題。
   解法：多架構**別用單一 runner + QEMU**，各架構跑在原生 runner（就是本 repo CI 的做法）。arm64 那份不受影響（AVX 是 x86 專屬）。

## 結構

```
.
├── Dockerfile                          # base image（mise pin + Claude Code）
├── .github/workflows/build-base.yml    # 多架構 build & push 到 GHCR
└── example/                            # 下游用法範例
    ├── mise.toml
    └── .devcontainer/
        ├── Dockerfile
        └── devcontainer.json
```
