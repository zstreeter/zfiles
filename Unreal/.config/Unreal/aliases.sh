#!/usr/bin/env bash

# Function to generate project files
ue-generate() {
  UnrealBuildTool -projectfiles -project="$1" -game -engine -Makefile
}

# Function to build the project
ue-build() {
  ~/.software/UnrealEngine/Engine/Build/BatchFiles/Linux/RunMono.sh ~/.software/UnrealEngine/Engine/Binaries/DotNET/UnrealBuildTool.exe "$2" Development Linux -project="$1" -game -engine
}

# Function to launch the Unreal Editor
ue-launch() {
  ~/.software/UnrealEngine/Engine/Binaries/Linux/UnrealEditor "$1"
}
