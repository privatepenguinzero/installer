#!/bin/bash

# List of packages to install
packages=(
  curl
  git 
  vim
  htop

# Add more packages here
)

# Load the distribution information from /etc/os-release
if [ -f /etc/os-release ]; then
    . /etc/os-release
else
    echo "Unable to detect the distribution!"
    exit 1
fi

# Combine ID and ID_LIKE for a broader distribution classification
os_family="$ID"
if [ -n "$ID_LIKE" ]; then
    os_family="$os_family $ID_LIKE"
fi

# Set the package manager and related commands based on the distribution family
pkg_manager=""
install_cmd=""
update_cmd=""

case "$os_family" in
    *debian*|*ubuntu*|*linuxmint*|*pop*)
        pkg_manager="apt"
        install_cmd="install -y"
        update_cmd="update"
        ;;
    *fedora*|*rhel*|*centos*|*almalinux*|*rocky*)
        # Use yum for CentOS, otherwise dnf
        if [[ "$os_family" == *centos* ]]; then
            pkg_manager="yum"
        else
            pkg_manager="dnf"
        fi
        install_cmd="install -y"
        update_cmd="check-update"
        ;;
    *arch*|*manjaro*)
        pkg_manager="pacman"
        install_cmd="-S --noconfirm"
        update_cmd="-Syu --noconfirm"
        ;;
    *opensuse*|*tumbleweed*)
        pkg_manager="zypper"
        install_cmd="install -y"
        update_cmd="refresh"
        ;;
    *)
        echo "Unsupported distribution: $ID"
        exit 1
        ;;
esac

# Update the package repository if an update command is defined
if [ -n "$update_cmd" ]; then
    echo "Updating repositories with: sudo $pkg_manager $update_cmd"
    sudo "$pkg_manager" "$update_cmd"
fi

# Install the packages from the list
echo "Installing packages: ${packages[@]}"
sudo "$pkg_manager" $install_cmd "${packages[@]}"

echo "Installation complete!"
