# esp32-firmware nostd example

Minimal bare-metal ESP32 firmware (esp-hal, no ESP-IDF at all) —
demonstrates `mkRustESPFirmware` with `type = "nostd"`
(`../../../nix/packages/mkRustESPFirmware.nix`). See `../std` for the
esp-idf-svc/FreeRTOS alternative.

## Hermetic build

```sh
nix build .#default   # from inside this directory
```

No toolchain setup needed — this fetches the Xtensa Rust toolchain
hermetically (no ESP-IDF needed for this one, unlike ../std). Produces a
plain ELF, not a flashable image.

## Real build (flash/monitor a device)

```sh
cargo install espup espflash
espup install
source ~/export-esp.sh   # re-run in every new shell

cargo build --release
cargo run --release      # flashes over USB and opens the serial monitor
```
