//! Minimal `no_std` ESP32 firmware example, built via `mkRustESPFirmware`
//! (see ../../../nix/packages/mkRustESPFirmware.nix and this directory's
//! own flake.nix). Demonstrates the bare-metal side of the esp-rs
//! ecosystem (esp-hal, no ESP-IDF at all) — see ../std for the
//! esp-idf-svc/FreeRTOS alternative.
#![no_std]
#![no_main]

use esp_backtrace as _;
use esp_hal::{main, time::Instant};

esp_bootloader_esp_idf::esp_app_desc!();

#[main]
fn main() -> ! {
    esp_println::logger::init_logger_from_env();
    let _peripherals = esp_hal::init(esp_hal::Config::default());

    loop {
        esp_println::println!("Hello from ESP32 (no_std)!");

        let now = Instant::now();
        while now.elapsed().as_millis() < 1000 {}
    }
}
