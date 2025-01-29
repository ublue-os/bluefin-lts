## My Additions

Added Niri, xwayland-satellite, swaybg, swayidle, swaylock and mako.

## Building

To build locally and then spit out a VM: 

```
just build
just build-iso ghcr.io/markupstart/bluefin-lts
```
qcow2 file is written to the `output/` directory. Username and password are `centos`/`centos`
