# Meshline

Offline-first Bluetooth mesh messenger for when the internet and cell service are down.

## Credit

Meshline is based on [bitchat](https://github.com/permissionlesstech/bitchat), released into the public domain under the Unlicense. The original README is kept in UPSTREAM_README.md and the original LICENSE is retained.

## Links

- Bluetooth LE mesh (from bitchat), always on.
- Wi-Fi peer link (MultipeerConnectivity) while the app is open; bridged with Bluetooth.
- Optional Meshtastic LoRa radio (Settings > Connectivity > LoRa radio). Meshline frames ride the radio's PRIVATE_APP port, split into chunks of up to 233 bytes, rate limited and limited to text, private messages, handshakes, envelopes, board posts and throttled announces. The Meshtastic protobuf subset is hand-written from public field numbers; no Meshtastic (GPL) code or generated files are included.
