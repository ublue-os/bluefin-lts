
#!/usr/bin/bash

PIXI_BIN_DIR="$HOME/.pixi/bin"

if [[ -d "$PIXI_BIN_DIR" ]]; then
  if [[ ":$PATH:" != *":$PIXI_BIN_DIR:"* ]]; then
    export PATH="$PIXI_BIN_DIR:$PATH"
  fi
fi