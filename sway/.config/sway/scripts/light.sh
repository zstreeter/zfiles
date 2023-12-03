#!/bin/sh

location=$(curl -s https://ipinfo.io/json | jq -r '.loc // empty')

if [ -n "$location" ]; then
	latitude=$(echo "$location" | cut -d ',' -f 1)
	longitude=$(echo "$location" | cut -d ',' -f 2)

	echo "Latitude: $latitude"
	echo "Longitude: $longitude"

	# Now you can use the obtained latitude and longitude with wlsunset
	wlsunset -l "$latitude" -L "$longitude"
else
	echo "Failed to fetch location information."
fi
