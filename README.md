# dirkeys.vim

按项目加载本地快捷键配置，并检测冲突。

## 特性

- 自动检测 Vim 启动目录下的 `.vim/` 文件夹
- 递归、按字母序 source 其中的 `.vim` 文件
- 加载前后做映射快照，检测：
  - 覆盖全局映射（覆盖 vimrc / 其他插件已定义的键）
  - 本地文件之间的重复定义
- 可配置冲突级别：`warn` / `error` / `silent`
- `:DirkeysCheck` 静态预检，不执行文件即可扫描潜在冲突

## 安装

任意插件管理器均可，例如 vim-plug：

```vim
Plug 'yourname/dirkeys.vim'