# esp32-firmware std example

Minimal `std` ESP32 firmware (esp-idf-svc, running atop ESP-IDF/FreeRTOS) —
demonstrates `mkRustESPFirmware` (`../../../nix/packages/mkRustESPFirmware.nix`).
See `../nostd` for the bare-metal (esp-hal, no ESP-IDF) alternative.

## Hermetic build

```sh
nix build .#default   # from inside this directory
```

No toolchain setup needed — this fetches everything (Xtensa Rust, ESP-IDF,
`ldproxy`) hermetically. Produces a plain ELF, not a flashable image.

## Real build (flash/monitor a device)

```sh
cargo install espup ldproxy espflash
espup install
source ~/export-esp.sh   # re-run in every new shell

cargo build --release
cargo run --release      # flashes over USB and opens the serial monitor
```
