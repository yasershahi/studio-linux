# WordPress Studio for Linux

Unofficial AppImage packaging for [Studio by WordPress.com](https://github.com/Automattic/studio).

## Quick Install

You can download the latest AppImage from the [releases page](https://github.com/yasershahi/studio-appimage/releases) and just run it!.

Alternatively, you can use [Gear Lever](https://flathub.org/apps/com.rafaelmardojai.GearLever), a Flatpak application for managing AppImages.

If AppImages do not run on your system, you might be missing `fuse` (Filesystem in Userspace). Install it using your distribution's package manager:

```bash
# Debian/Ubuntu
sudo apt-get install libfuse2

# Fedora
sudo dnf install fuse

# Arch Linux
sudo pacman -S fuse2
```

## Disclaimer

This is not an official package and is not affiliated with WordPress.com or Automattic Inc.
