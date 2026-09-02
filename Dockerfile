FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# --- mise：裝到系統路徑，任何 user 都能呼叫 ---
USER root
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# --- 切回 devcontainer 預設非 root user ---
USER vscode
ENV HOME=/home/vscode

# shims 模式：讓「build 期間的 RUN」和非互動 shell 也能用 mise 裝的工具
ENV PATH="${HOME}/.local/share/mise/shims:${HOME}/.local/bin:${PATH}"

# 互動 shell 額外啟用 activate（補全、自動切版本等體驗較好）
RUN echo 'eval "$(mise activate bash)"' >> ~/.bashrc \
 && echo 'eval "$(mise activate zsh)"'  >> ~/.zshrc

# --- Claude Code：native installer，不依賴 node ---
# 下載到檔案再執行（避免 curl|bash 吞掉 curl 的錯誤），帶 UA + retry 盡量繞過 CDN 對 CI IP 的擋
RUN curl -fsSL --retry 5 --retry-all-errors \
      -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128 Safari/537.36" \
      https://claude.ai/install.sh -o /tmp/claude-install.sh \
 && bash /tmp/claude-install.sh \
 && rm -f /tmp/claude-install.sh

# 冒煙測試，build 期就抓錯
RUN mise --version && claude --version
