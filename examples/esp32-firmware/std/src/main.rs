//! Minimal `std` ESP32 firmware example, built via `mkRustESPFirmware` (see
//! ../../../nix/packages/mkRustESPFirmware.nix and this directory's own
//! flake.nix). Demonstrates the "std" side of the esp-rs ecosystem
//! (esp-idf-svc, running atop ESP-IDF/FreeRTOS) — see ../nostd for the
//! bare-metal (esp-hal, no ESP-IDF at all) alternative.

fn main() {
    esp_idf_svc::sys::link_patches();
    esp_idf_svc::log::EspLogger::initialize_default();

    loop {
        log::info!("Hello from ESP32 (std)!");
        std::thread::sleep(std::time::Duration::from_secs(1));
    }
}
