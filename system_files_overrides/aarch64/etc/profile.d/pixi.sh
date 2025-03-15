
#!/usr/bin/bash

PIXI_BIN_DIR="$HOME/.pixi/bin"

if [[ -d "$PIXI_BIN_DIR" ]]; then
  if [[ ":$PATH:" != *":$PIXI_BIN_DIR:"* ]]; then
    export PATH="$PIXI_BIN_DIR:$PATH"
    echo "Added pixi bin directory to PATH: $PIXI_BIN_DIR"
  else
    echo "pixi bin directory already in PATH."
  fi
else
  echo "pixi bin directory not found: $PIXI_BIN_DIR"
fi