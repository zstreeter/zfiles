#!/usr/bin/env bash

set -ex

mkdir -p $HOME/.software
SOFTWARE_DIR=$HOME/.software

PREFIX="$HOME/.local"
MESON_INSTALL_DIR="-Dprefix=$HOME/.local"

# A "nice to have"
# Great collection of dmeneu scripts to build off of
# git clone https://gitlab.com/dwt1/dmscripts.git

# zsh ZAP
zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1

# F-Sy-H (ZAP doesn't have this yet. Setup is done in script's install.sh)
git clone https://github.com/z-shell/F-Sy-H /f-sy-h $HOME/.local/share/zap/plugins/f-sy-h

# Conda
mkdir -p $HOME/.local/miniconda
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/.local/miniconda/miniconda.sh
bash $HOME/.local/miniconda/miniconda.sh -b -u -p $HOME/.local/miniconda
rm -rf $HOME/.local/miniconda/miniconda.sh

# tpm --- Tmux plugin manager
git clone https://github.com/tmux-plugins/tpm $HOME/.config/tmux/plugins/tpm

# Autotiling
git clone https://github.com/nwg-piotr/autotiling.git
mv ./autotiling/autotiling/main.py $HOME/.local/bin/autotiling
chmod +x $HOME/.local/bin/autotiling

# Bemenu
git clone https://github.com/Cloudef/bemenu.git
pushd bemenu
make
make install PREFIX=$HOME/.local
popd

# Chafa
git clone https://github.com/hpjansson/chafa.git
pushd chafa
./autogen.sh
make
sudo make install
popd

# ctpv
git clone https://github.com/NikitaIvanovV/ctpv.git
pushd ctpv
make
sudo make install
popd

# getnf --- select 17) FiraMono
git clone https://github.com/ronniedroid/getnf.git
pushd getnf
./install.sh
popd

# kmonad
git clone https://github.com/kmonad/kmonad.git $SOFTWARE_DIR/kmonad
pushd $SOFTWARE_DIR/kmonad
stack install
popd

# Mako notifications
git clone https://github.com/emersion/mako.git
pushd mako
meson "$MESON_INSTALL_DIR" build
ninja -C build
popd
pushd mako/build
meson install
popd

# neovim
git clone https://github.com/neovim/neovim.git
pushd neovim
make CMAKE_BUILD_TYPE=Release CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$HOME/.local"
make install
popd

# nwg-launchers
git clone https://github.com/nwg-piotr/nwg-launchers.git
pushd nwg-launchers
meson "$MESON_INSTALL_DIR" builddir -Dbuildtype=release
ninja -C builddir
popd
pushd nwg-launchers/builddir
meson install
popd

# pamixer
git clone https://github.com/cdemoulins/pamixer.git
pushd pamixer
meson setup "$MESON_INSTALL_DIR" build
meson compile -C build
popd
pushd pamixer/build
meson install
popd

# pandoc
git clone https://github.com/jgm/pandoc.git $SOFTWARE_DIR/pandoc
pushd $SOFTWARE_DIR/pandoc
stack setup
stack install pandoc-cli
popd

# qutebrowser
git clone https://github.com/qutebrowser/qutebrowser.git $SOFTWARE_DIR/qutebrowser
pushd $SOFTWARE_DIR/qutebrowser
python3 scripts/mkvenv.py
popd

# # cava
git clone https://github.com/karlstav/cava.git $SOFTWARE_DIR/cava
pushd $SOFTWARE_DIR/cava
./autogen.sh
./configure --prefix=$PREFIX
make install
popd

# # Waybar
git clone https://github.com/Alexays/Waybar.git $SOFTWARE_DIR/Waybar
pushd $SOFTWARE_DIR/Waybar
meson "$MESON_INSTALL_DIR" build
ninja -C build install
popd

# wlsunset
git clone https://github.com/kennylevinsen/wlsunset.git $SOFTWARE_DIR/wlsunset
pushd $SOFTWARE_DIR/wlsunset
meson "$MESON_INSTALL_DIR" build
ninja -C build install
popd

# lf
env CGO_ENABLED=0 go install -ldflags="-s -w" github.com/gokcehan/lf@latest # not exactly sure where this puts the lf binary

# epub-thumbnailer
git clone https://github.com/marianosimone/epub-thumbnailer.git $SOFTWARE_DIR/epub-thumbnailer
pushd $SOFTWARE_DIR/epub-thumbnailer
sudo python3 install.py install
popd

# Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

# FZF
git clone https://github.com/junegunn/fzf.git $SOFTWARE_DIR/.fzf
$SOFTWARE_DIR/.fzf/install --no-bash --no-fish --all

# Nodejs
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
NODE_MAJOR=20
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt-get update && sudo apt-get install nodejs -y

# LunarVim
git clone https://github.com/LunarVim/LunarVim $SOFTWARE_DIR/LunarVim
$HOME/.software/.LunarVim/utils/installer/install.sh -y

# xdg-ninja
git clone https://github.com/b3nj5m1n/xdg-ninja.git $SOFTWARE_DIR/xdg-ninja.git
echo "Can use xdg-ninja.sh to check how clean $HOME folder is"

# bat colors
bat cache --build
