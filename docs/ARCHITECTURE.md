# AshenKingdoms — Architecture and Implementation Status

## Runtime facts

- Engine: Godot 4.6, GDScript, GL Compatibility renderer.
- Entry scene: `res://scenes/boot/Main.tscn`.
- The current main script creates the prototype world, player, camera, four enemies, NPC, progression, quest, inventory, save system and HUD at runtime.
- `scripts/core/server.gd` is a dedicated-server scaffold only. It does not open an ENet peer, authenticate peers, replicate players, validate attacks, or run authoritative combat.
- The existing smoke tests cover progression, quest state and JSON save handling. They do not prove Android touch usability, multiplayer correctness or release readiness.

## Current implementation in this branch

- A reusable `scenes/ui/TouchControls.tscn` and `scripts/ui/touch_controls.gd` provide touch-screen movement, camera-look gestures, jump, attack, interact and inventory actions.
- Touch controls are instantiated by the existing main scene script and are hidden on non-mobile platforms.
- Camera look is routed through `player_camera.gd` so mouse and touch gestures use the same rotation method.

## Network architecture — planned, not implemented

1. Create an ENetMultiplayerPeer only after the user selects Host or Join.
2. Define an explicit session state machine: offline, hosting, connecting, connected, disconnecting, failed.
3. Assign player identity from `multiplayer.get_remote_sender_id()`; never trust a client-supplied peer identity.
4. Spawn and remove players through a server-owned MultiplayerSpawner or explicit server RPCs.
5. Validate movement speed, world bounds, cooldown, target range, line of sight and alive state on the server.
6. Apply damage, death, quest progress and rewards only on the server; replicate the resulting state to clients.
7. Add reconnection, disconnect cleanup, protocol versioning, rate limits and automated two-client tests before production use.

## Release gates

- Run Godot 4.6 headless import and `tests/gameplay_smoke_test.gd`.
- Export Android and Web in separate jobs and retain build artifacts.
- Install the APK on a physical Android device; test movement, camera, combat, dialogue, inventory, save/load, orientation and safe areas.
- Run two clients against a dedicated server before claiming multiplayer support.
- Keep the server scaffold clearly labelled until ENet sessions and authority checks exist.
