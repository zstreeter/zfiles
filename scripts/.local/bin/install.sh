#!/usr/bin/env bash

set -ex

mkdir -p $HOME/.software
SOFTWARE_DIR=$HOME/.software

PREFIX="$HOME/.local"
MESON_INSTALL_DIR="-Dprefix=$HOME/.local"

# Function to check if a directory is a git repository and update or skip
clone_or_update_repo() {
    local repo_url=$1
    local dest_dir=$2

    if [ -d "$dest_dir/.git" ]; then
        echo "$dest_dir already exists and is a Git repository. Updating..."
        git -C $dest_dir pull
    elif [ -d "$dest_dir" ]; then
        echo "$dest_dir already exists but is not a Git repository. Skipping clone..."
    else
        echo "Cloning $repo_url into $dest_dir"
        git clone $repo_url $dest_dir
    fi
}

# Function to safely move a file if it exists
safe_move() {
    local src_file=$1
    local dest_file=$2

    if [ -f "$src_file" ]; then
        mv -f "$src_file" "$dest_file"
        chmod +x "$dest_file"
        echo "Moved $src_file to $dest_file."
    else
        echo "File $src_file not found, skipping move."
    fi
}

# Obsidian
if ! command -v obsidian &> /dev/null; then
    sudo snap install obsidian --classic
else
    echo "Obsidian is already installed."
fi

# Install Stack (Haskell)
if ! command -v stack &> /dev/null; then
    curl -sSL https://get.haskellstack.org/ | sh
else
    echo "Haskell Stack is already installed."
fi

# eza (replacement for ls)
if ! command -v eza &> /dev/null; then
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt update
    sudo apt install -y eza
else
    echo "eza is already installed."
fi

# WezTerm
if ! command -v wezterm &> /dev/null; then
    curl -fsSL https://apt.fury.io/wez/gpg.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
    echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' | sudo tee /etc/apt/sources.list.d/wezterm.list
    sudo apt update && sudo apt install wezterm
else
    echo "WezTerm is already installed."
fi

# Zsh ZAP
if [ ! -d "$HOME/.local/share/zap" ]; then
    zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1
else
    echo "ZAP is already installed."
fi

# F-Sy-H (ZAP doesn't have this yet. Setup is done in script's install.sh)
clone_or_update_repo https://github.com/z-shell/F-Sy-H $HOME/.local/share/zap/plugins/f-sy-h

# Conda
if [ ! -d "$HOME/.local/miniconda" ]; then
    mkdir -p $HOME/.local/miniconda
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O $HOME/.local/miniconda/miniconda.sh
    bash $HOME/.local/miniconda/miniconda.sh -b -u -p $HOME/.local/miniconda
    rm -rf $HOME/.local/miniconda/miniconda.sh
else
    echo "Miniconda is already installed."
fi

# tpm --- Tmux plugin manager
clone_or_update_repo https://github.com/tmux-plugins/tpm $HOME/.config/tmux/plugins/tpm

# Autotiling
if ! command -v autotiling &> /dev/null; then
    clone_or_update_repo https://github.com/nwg-piotr/autotiling.git autotiling
    safe_move autotiling/autotiling/main.py $HOME/.local/bin/autotiling
else
    echo "Autotiling is already installed."
fi

# Bemenu
if ! command -v bemenu &> /dev/null; then
    clone_or_update_repo https://github.com/Cloudef/bemenu.git bemenu
    pushd bemenu
    make
    make install PREFIX=$HOME/.local
    popd
else
    echo "Bemenu is already installed."
fi

# Chafa
if ! command -v chafa &> /dev/null; then
    clone_or_update_repo https://github.com/hpjansson/chafa.git chafa
    pushd chafa
    ./autogen.sh
    make
    sudo make install
    popd
else
    echo "Chafa is already installed."
fi

# ctpv
if ! command -v ctpv &> /dev/null; then
    clone_or_update_repo https://github.com/NikitaIvanovV/ctpv.git ctpv
    pushd ctpv
    make
    sudo make install
    popd
else
    echo "CTPV is already installed."
fi

# getnf --- select 17) FiraMono
if [ ! -d "getnf" ]; then
    clone_or_update_repo https://github.com/ronniedroid/getnf.git getnf
    pushd getnf
    ./install.sh
    popd
else
    echo "GetNF is already installed."
fi

# kmonad
if ! command -v kmonad &> /dev/null; then
    clone_or_update_repo https://github.com/kmonad/kmonad.git $SOFTWARE_DIR/kmonad
    pushd $SOFTWARE_DIR/kmonad
    stack install
    popd
else
    echo "Kmonad is already installed."
fi

# Mako notifications
if ! command -v mako &> /dev/null; then
    clone_or_update_repo https://github.com/emersion/mako.git mako
    pushd mako
    meson "$MESON_INSTALL_DIR" build
    ninja -C build
    meson install -C build
    popd
else
    echo "Mako is already installed."
fi

# Neovim
if ! command -v nvim &> /dev/null; then
    clone_or_update_repo https://github.com/neovim/neovim.git neovim
    pushd neovim
    make CMAKE_BUILD_TYPE=Release CMAKE_EXTRA_FLAGS="-DCMAKE_INSTALL_PREFIX=$HOME/.local"
    make install
    popd
else
    echo "Neovim is already installed."
fi

# nwg-launchers
if ! command -v nwg-drawer &> /dev/null; then
    clone_or_update_repo https://github.com/nwg-piotr/nwg-launchers.git nwg-launchers
    pushd nwg-launchers
    meson "$MESON_INSTALL_DIR" builddir -Dbuildtype=release
    ninja -C builddir
    meson install -C builddir
    popd
else
    echo "Nwg-launchers are already installed."
fi

# pamixer
if ! command -v pamixer &> /dev/null; then
    clone_or_update_repo https://github.com/cdemoulins/pamixer.git pamixer
    pushd pamixer
    meson setup "$MESON_INSTALL_DIR" build
    meson compile -C build
    meson install -C build
    popd
else
    echo "Pamixer is already installed."
fi

# pandoc
if ! command -v pandoc &> /dev/null; then
    clone_or_update_repo https://github.com/jgm/pandoc.git $SOFTWARE_DIR/pandoc
    pushd $SOFTWARE_DIR/pandoc
    stack setup
    stack install pandoc-cli
    popd
else
    echo "Pandoc is already installed."
fi

# qutebrowser
if ! command -v qutebrowser &> /dev/null; then
    clone_or_update_repo https://github.com/qutebrowser/qutebrowser.git $SOFTWARE_DIR/qutebrowser
    pushd $SOFTWARE_DIR/qutebrowser
    python3 scripts/mkvenv.py
    popd
else
    echo "Qutebrowser is already installed."
fi

# cava
if ! command -v cava &> /dev/null; then
    clone_or_update_repo https://github.com/karlstav/cava.git $SOFTWARE_DIR/cava
    pushd $SOFTWARE_DIR/cava
    ./autogen.sh
    ./configure --prefix=$PREFIX
    make install
    popd
else
    echo "Cava is already installed."
fi

# Waybar
if ! command -v waybar &> /dev/null; then
    clone_or_update_repo https://github.com/Alexays/Waybar.git $SOFTWARE_DIR/Waybar
    pushd $SOFTWARE_DIR/Waybar
    meson "$MESON_INSTALL_DIR" build
    ninja -C build install
    popd
else
    echo "Waybar is already installed."
fi

# wlsunset
if ! command -v wlsunset &> /dev/null; then
    clone_or_update_repo https://github.com/kennylevinsen/wlsunset.git $SOFTWARE_DIR/wlsunset
    pushd $SOFTWARE_DIR/wlsunset
    meson "$MESON_INSTALL_DIR" build
    ninja -C build install
    popd
else
    echo "Wlsunset is already installed."
fi

# epub-thumbnailer
if [ ! -d "$SOFTWARE_DIR/epub-thumbnailer" ]; then
    clone_or_update_repo https://github.com/marianosimone/epub-thumbnailer.git $SOFTWARE_DIR/epub-thumbnailer
    pushd $SOFTWARE_DIR/epub-thumbnailer
    sudo python3 install.py install
    popd
else
    echo "epub-thumbnailer is already installed."
fi

# nvtop
if ! command -v nvtop &> /dev/null; then
    clone_or_update_repo https://github.com/Syllo/nvtop.git $SOFTWARE_DIR/nvtop
    mkdir -p $SOFTWARE_DIR/nvtop/build
    pushd $SOFTWARE_DIR/nvtop/build
    cmake .. -DAMDGPU_SUPPORT=ON
    make DESTDIR="$HOME/.local/bin" install
    popd
else
    echo "NVTOP is already installed."
fi

# Rust
if ! command -v rustc &> /dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    rustup update
else
    echo "Rust is already installed."
fi

# Yazi
if ! command -v yazi &> /dev/null; then
    cargo install --locked yazi-fm yazi-cli
    ya pack -a yazi-rs/plugins:full-border
    ya pack -a yazi-rs/plugins:smart-enter
    ya pack -a yazi-rs/flavors:catppuccin-macchiato
else
    echo "Yazi is already installed."
fi

# FZF
if [ ! -d "$SOFTWARE_DIR/.fzf" ]; then
    clone_or_update_repo https://github.com/junegunn/fzf.git $SOFTWARE_DIR/.fzf
    $SOFTWARE_DIR/.fzf/install --no-bash --no-fish --all
else
    echo "FZF is already installed."
fi

# Nodejs
if ! command -v node &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    NODE_MAJOR=20
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list
    sudo apt-get update && sudo apt-get install nodejs -y
else
    echo "Node.js is already installed."
fi

# xdg-ninja
if [ ! -d "$SOFTWARE_DIR/xdg-ninja" ]; then
    clone_or_update_repo https://github.com/b3nj5m1n/xdg-ninja.git $SOFTWARE_DIR/xdg-ninja
    echo "Can use xdg-ninja.sh to check how clean $HOME folder is"
else
    echo "xdg-ninja is already installed."
fi

# bat colors
# bat cache --build
