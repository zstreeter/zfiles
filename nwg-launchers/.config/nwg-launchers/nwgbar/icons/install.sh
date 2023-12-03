#!/bin/bash

if [ ! -d "/usr/share/nwg-launchers/nwgbar/images" ]; then
	mkdir -p "/usr/share/nwg-launchers/nwgbar/images"
fi
cp -r ./* /usr/share/nwg-launchers/nwgbar/images/
