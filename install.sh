#!/usr/bin/env bash

# Determine the directory where the script is located
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_DIR="$SCRIPT_DIR"

# Prompt the user for the name of this machine's configuration
read -p "Enter the name for this machine's configuration (e.g., hostname or purpose): " CONFIG_NAME

# Create a directory for this machine's configuration within the repo
mkdir -p "$CONFIG_DIR/$CONFIG_NAME"

# Copy the existing /etc/nixos/ contents to the new configuration directory
echo "Copying existing /etc/nixos/ contents to $CONFIG_DIR/$CONFIG_NAME/."
sudo cp -R /etc/nixos/* "$CONFIG_DIR/$CONFIG_NAME/"

# Backup the existing /etc/nixos and replace it with a symlink to the new configuration
echo "Backing up /etc/nixos to /etc/nixos.backup and setting up the symlink."
sudo mv /etc/nixos /etc/nixos.backup
sudo ln -s "$CONFIG_DIR/$CONFIG_NAME" /etc/nixos

# Ensure the appropriate permissions are set on the new configuration directory
sudo chown -R "$USER":$(id -gn "$USER") "$CONFIG_DIR/$CONFIG_NAME"
sudo chmod -R 700 "$CONFIG_DIR/$CONFIG_NAME"

# Git add and commit the new configuration
cd "$CONFIG_DIR"
git add "$CONFIG_NAME"
git commit -m "Added configuration for $CONFIG_NAME"

# Option to clone and add ixnay to PATH
# only do if $HOME/ixnay doesn't exist
if [ ! -d "$HOME/ixnay" ]; then
    read -p "Do you want to clone the ixnay tool and add it to PATH temporarily? (y/n): " clone_ixnay
    if [ "$clone_ixnay" = "y" ]; then
        git clone https://github.com/pmarreck/ixnay ~/ixnay
        echo "Adding ixnay to PATH."
        export PATH=$PATH:~/ixnay
    fi
fi

# Option to clone dotfiles repository
# only do if $HOME/dotfiles doesn't exist
if [ ! -d "$HOME/dotfiles" ]; then
    read -p "Do you want to clone your dotfiles repository into $HOME/dotfiles? (y/n): " clone_dotfiles
    if [ "$clone_dotfiles" = "y" ]; then
        git clone https://github.com/pmarreck/dotfiles ~/dotfiles
    fi
fi

# Option to clone dotconfig repository
# only do if $HOME/.config isn't already a git repository
if [ ! -d "$HOME/.config/.git" ]; then
    read -p "Do you want to clone your dotconfig repository into $HOME/.config (backing up any existing .config directory first)? (y/n): " clone_dotconfig
    if [ "$clone_dotconfig" = "y" ]; then
        if [ -d "$HOME/.config" ]; then
            echo "Backing up existing .config directory."
            mv ~/.config ~/.config.backup
        fi
        git clone https://github.com/pmarreck/dotconfig ~/.config
    fi
fi

echo "Setup complete. Your configuration has been linked and backed up."
