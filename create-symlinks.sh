#!/bin/bash

# Detect operating system and set the source directory accordingly
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS_DIR="linux"
  echo "Linux detected, using linux configuration."
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS_DIR="mac"
  echo "macOS detected, using mac configuration."
else
  echo "Unknown operating system. Defaulting to mac configuration."
  OS_DIR="mac"
fi

# Define source directories
DOTFILES_DIR="$HOME/Documents/dotFiles/$OS_DIR"
GENERAL_DIR="$HOME/Documents/dotFiles/general"
CONFIG_DIR="$HOME/.config"

# Create .config directory if it doesn't exist
mkdir -p "$CONFIG_DIR"

# Check if OS-specific dotfiles directory exists
if [ ! -d "$DOTFILES_DIR" ]; then
  echo "Warning: OS-specific dotfiles directory $DOTFILES_DIR does not exist."
fi

# Check if general dotfiles directory exists
if [ ! -d "$GENERAL_DIR" ]; then
  echo "Warning: General dotfiles directory $GENERAL_DIR does not exist."
fi

# Function to create symlinks for config folders
create_config_symlinks() {
  local source_dir=$1

  if [ ! -d "$source_dir" ]; then
    return
  fi

  echo "Creating symlinks for config folders from $source_dir..."

  # Loop through all directories in the source directory
  for folder in $(find "$source_dir" -maxdepth 1 -type d -not -path "$source_dir"); do
    folder_name=$(basename "$folder")

    # Skip hidden directories (those starting with .)
    if [[ "$folder_name" != .* ]]; then
      # Remove existing destination if it exists
      if [ -e "$CONFIG_DIR/$folder_name" ]; then
        echo "Removing existing $CONFIG_DIR/$folder_name"
        rm -rf "$CONFIG_DIR/$folder_name"
      fi

      # Create symlink
      echo "Creating symlink: $CONFIG_DIR/$folder_name -> $folder"
      ln -sf "$folder" "$CONFIG_DIR/$folder_name"
    fi
  done
}

# Function to create symlinks for home directory files (dotfiles)
create_home_symlinks() {
  local source_dir=$1

  if [ ! -d "$source_dir" ]; then
    return
  fi

  echo "Creating symlinks for home directory files from $source_dir..."

  # Loop through all hidden files in the source directory
  for file in $(find "$source_dir" -maxdepth 1 -type f -name ".*"); do
    file_name=$(basename "$file")

    # Remove existing destination if it exists
    if [ -e "$HOME/$file_name" ]; then
      echo "Removing existing $HOME/$file_name"
      rm -f "$HOME/$file_name"
    fi

    # Create symlink
    echo "Creating symlink: $HOME/$file_name -> $file"
    ln -sf "$file" "$HOME/$file_name"
  done
}

# Process OS-specific dotfiles first
create_config_symlinks "$DOTFILES_DIR"
create_home_symlinks "$DOTFILES_DIR"

# Then process general dotfiles (these will override OS-specific ones if there are conflicts)
create_config_symlinks "$GENERAL_DIR"
create_home_symlinks "$GENERAL_DIR"

echo "Symlinks created successfully!"
