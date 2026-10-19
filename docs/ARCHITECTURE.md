# AshenKingdoms — Architecture and Implementation Status

## Project entry points

- Engine: Godot 4.6, GDScript, GL Compatibility renderer.
- Configured entry scene: `res://scenes/ui/MainMenu.tscn`.
- Single-player scene: `res://scenes/boot/Main.tscn`.
- Experimental network scene: `res://scenes/network/MultiplayerArena.tscn`.
- The single-player scene creates its world, player, camera, enemies, NPC, progression, quest state, inventory, local save system, and HUD at runtime.

## Implemented prototype areas

- Single-player movement, camera, combat, health, enemies, inventory/potions, progression, a sample quest, dialogue/NPC interaction and local JSON save/load.
- Touch controls for movement, camera look, combat, jump, interaction and inventory; physical-device usability still needs manual validation.
- An ENet host/client prototype on Desktop and Android using `scripts/core/network_manager.gd`, `scripts/ui/main_menu.gd`, and `scripts/networking/`.
- A separate network arena with network avatars/enemies, authoritative handling for the prototype's movement/combat/health and a sample kill-quest.
- CI coverage includes resource/script loading, gameplay smoke and regression tests, player-character checks, network combat smoke checks, a local ENet host/client loopback test, content package tests, and Android/Web exports.

## Network startup and limitations

The configured project starts in `MainMenu.tscn`. In headless mode, `scripts/ui/main_menu.gd` detects server mode and starts an ENet host through `NetworkManager.start_host()`; the tested command is:

```bash
godot --headless --path . -- --server --server-port=7777
```

Do not treat `scripts/core/server.gd` as the implementation of that path: it still contains a placeholder scaffold and is not the active startup route for the configured main scene.

This network functionality is **experimental, not production-ready**. It does not provide account authentication, persistent network saves, a public managed server, complete synchronization of inventory/dialogue, or a production anti-cheat/security model. Local CI loopback success proves connectivity in the CI environment only; test on physical Android devices and across the intended network before release.

## Content and assets

- Optional downloadable content uses a signed catalog and SHA-256 integrity checks; production downloads remain disabled until a real HTTPS catalog, public key and hosting are configured.
- Asset tools organize and validate source/license records. The presence of tooling does not imply that a final player GLB, external audio or other finished art has been added.
- Read [the documentation index](README.md), [the detailed technical architecture](TECHNICAL_ARCHITECTURE.md), [the test plan](TEST_PLAN.md), [networking notes](NETWORKING.md), and [asset credits](ASSET_CREDITS.md) for operational detail.

## Release gates

- Run the validation workflow and verify the relevant job/step results for the exact commit.
- Install the debug APK on a physical Android device; test movement, camera, combat, dialogue, inventory, save/load, orientation, safe areas and touch gestures.
- Test a host and a second physical client over the intended LAN/network, including disconnect/reconnect and failure cases.
- Confirm content-signing keys are handled outside the repository and test real content downloads only after configuring the catalog and HTTPS hosting.
- Keep all experimental systems explicitly labelled until their missing requirements and acceptance tests are complete.


## Approved target vs current platform support

The approved release target is solo and multiplayer gameplay on Android and Web. This is a product target, not current platform parity:

| Platform | Current known support | Release limitation |
|---|---|---|
| Desktop | Solo prototype and experimental ENet arena | No production authentication, persistent network saves or managed public service |
| Android | Solo prototype, touch UI, experimental ENet arena; CI creates a debug APK | Physical-device acceptance and production signing remain separate gates |
| Web | HTML5 export for solo play | ENet multiplayer is disabled; browser-compatible transport and its server path remain work items |

See [approved release scope](RELEASE_SCOPE_AR.md), [current project status](PROJECT_STATUS_AR.md), and [documentation maintenance rules](DOCUMENTATION_GUIDE_AR.md). Update this matrix when implementation or verified platform support changes.
