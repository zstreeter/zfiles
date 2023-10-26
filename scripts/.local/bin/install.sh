#!/usr/bin/env bash

set -ex

PREFIX="$HOME/.local"
MESON_INSTALL_DIR="-Dprefix=$HOME/.local"

# A "nice to have"
# Great collection of dmeneu scripts to build off of
# git clone https://gitlab.com/dwt1/dmscripts.git

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
git clone https://github.com/kmonad/kmonad.git
pushd kmonad
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
git clone https://github.com/jgm/pandoc.git
pushd pandoc
stack setup
stack install pandoc-cli
popd

# qutebrowser
git clone https://github.com/qutebrowser/qutebrowser.git
pushd qutebrowser
python3 scripts/mkvenv.py
popd

# # cava
git clone https://github.com/karlstav/cava.git
pushd cava
./autogen.sh
./configure --prefix=$PREFIX
make install
popd

# # Waybar
git clone https://github.com/Alexays/Waybar.git
pushd Waybar
meson "$MESON_INSTALL_DIR" build
ninja -C build install
popd

# wlsunset
git clone https://github.com/kennylevinsen/wlsunset.git
pushd wlsunset
meson "$MESON_INSTALL_DIR" build
ninja -C build install
popd

# lf
env CGO_ENABLED=0 go install -ldflags="-s -w" github.com/gokcehan/lf@latest # not exactly sure where this puts the lf binary

# bat colors
bat cache --build
