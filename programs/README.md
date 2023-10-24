# Programs

This directory will contain a running list of programs I get from the *apt* package manager. I'll create/update that list the next time I bring up a machine.

The rest of this README is dedicated to a few notes on setup for some of the programs I have to install from source.

List of Programs (`sudo apt install -y program`)

* fzf
* bat

## Cool Icons

[Candy-icons](https://github.com/EliverLara/candy-icons)
[Sweet-folder](https://github.com/EliverLara/Sweet-folders)

## Kmonad

Not sure how I had it setup before, then I had the sway exec on startup without `sudo` but this solution does require executing it with `sudo`

* First change the default editor:
  `sudo update-alternatives --config editor` and select vim
* Then set the kmonad command to not require password when using `sudo`
  `zstreet ALL=(ALL) NOPASSWD: /usr/bin/kmonad`
  Note: I built kmonad locally as `$USER` and copied it to `usr/bin`

## Qutebrowser

Note sure if I was using the ".venv" version or the "apt" one but now I'm using the ".venv" one.
The only caveat is I couldn't get their wrapper script to work so I did a small hack. Here's the script

```bash
cat /usr/local/bin/qutebrowser
pushd $HOME/zfiles/software/qutebrowser
.venv/bin/python3 -m qutebrowser "$@"
```
I may have symlinked it with `ln -s /home/zstreet/zfiles/software/qutebrowser/.venv/bin/qutebrowser /usr/local/bin/qutebrowser`

## Firefox

This is installed in case others want to use the machine.
Delete the snap version and install the apt version
```bash
sudo snap remove --purge firefox
sudo add-apt-repository ppa:mozillateam/ppa

echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox

echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:${distro_codename}";' | sudo tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox

sudo apt update
sudo apt install firefox
```

## Pipewire & Wireplumber

[pipewire-replace-pulseaudio-ubuntu](https://ubuntuhandbook.org/index.php/2022/04/pipewire-replace-pulseaudio-ubuntu-2204/)
[another_guide](https://gist.github.com/the-spyke/2de98b22ff4f978ebf0650c90e82027e?permalink_comment_id=3976215)
