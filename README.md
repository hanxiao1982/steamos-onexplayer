# steamos-onexplayer

OneXPlayer 掌机在类 SteamOS 发行版上的适配笔记。

当前已整理 Bazzite 与 CachyOS 的 OXP 内核模块位置、内核 patch 流程，以及最新版用户态栈：

- [docs/bazzite-cachyos-oxp-kernel.md](docs/bazzite-cachyos-oxp-kernel.md)

只适配这两个系统的最新版本时，按键映射可以不改 HHD，只走 InputPlumber。TDP / 风扇不在 InputPlumber 里，走 PowerStation + steamos-manager 和内核 `oxpec`。

不等主线合入时，用树外模块在两边本地编译、测试、安装：

- [docs/local-build-and-deploy.md](docs/local-build-and-deploy.md)
- 掌机能 SSH 时，从电脑拷仓库并远程跑完整步骤：[docs/ssh-deploy.md](docs/ssh-deploy.md)
- 工具：`kmod/`
