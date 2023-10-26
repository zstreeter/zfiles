# Installing Programs from Source

Some programs require installing from source. I've tried to automate this requirement with the `install.sh` script.

This install script should be ran **after** installing all the programs under the *protrams* directory, as many of these installations from source require most of those programs.

The idea is this *local* folder should be symlinked under `$HOME/.local` using stow, as all the other configs. You should symlinked this folder there before running the install script.


Be sure to change /usr/share/wayland-sessions/sway.desktop
to point to the modified execution point found in this *bin* directory. Using the above directions, it should be in the location shown below.

```bash
[Desktop Entry]
Comment=An i3-compatible Wayland compositor
Name=Sway
Exec=/home/zstreet/.local/bin/sway-run
Type=Application
```
