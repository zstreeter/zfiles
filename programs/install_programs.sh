#!/bin/sh

file_path="./program_list.txt"

if [ -f "$file_path" ]; then
  while IFS= read -r program; do
    if [ -n "$program" ] && [ ! "$program" = \#* ]; then
      sudo apt install -y "$program"
    fi
  done < "$file_path"

  echo "Installation of programs from $file_path completed."
else
  echo "File $file_path not found."
fi
