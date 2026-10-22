# AshenKingdoms — Repository Architecture Briefing

**Reviewed snapshot:** hardening/save-system-v1 at 0f117a3236e39cf1ed569d05915af3d440ea98b6  
**Review date:** 2026-10-22  
**Engine / language:** Godot 4.6 / GDScript  
**Scope:** Android and desktop PC; Web is an additional solo-play export target  
**Method:** Read-only inspection of GitHub tree, project settings, scenes, scripts, tests, documentation and workflows. This was not a local clone, interactive play session, penetration test or device test.

> **Branch warning:** This briefing describes the hardening branch, not the default main branch. At review time, hardening/save-system-v1 was 41 commits ahead of main and zero commits behind it. The improvements noted below should not be assumed present on main until merged.

## 1. Executive assessment

AshenKingdoms is a Godot 4.6 3D fantasy RPG prototype with two different runtime paths:

1. A local single-player vertical slice: dynamically constructed world, player, enemies, NPC/dialogue, inventory, progression, quests, HUD and local JSON persistence.
2. An independent ENet multiplayer arena used to exercise host/client lifecycle, server-side movement/combat/health, a small replicated player/enemy state, and a sample kill quest.

The repository also includes optional-content catalog/install tooling, asset provenance checks, automated Godot/Python tests and GitHub Actions workflows. These are useful foundations, but do not establish production readiness. The network arena is not the single-player world running online; the Web export is solo-play only; there is no persistent online save service or account authentication; and the checked-in asset manifest records only the project’s own SVG icon, not a finished production art/audio set.

The most important architectural property is the division between **implemented prototype behavior** and **target architecture**. The server owns core gameplay decisions in the network arena while input and presentation remain client-side. Remaining gates include broader RPC abuse protection, account/session identity, network tests beyond loopback, and physical Android/browser acceptance.

## 2. Repository baseline and evidence rules

### Snapshot identity

- Reviewed commit: [0f117a3](https://github.com/areagleegy/AshenKingdoms/commit/0f117a3236e39cf1ed569d05915af3d440ea98b6)
- Reviewed branch: [hardening/save-system-v1](https://github.com/areagleegy/AshenKingdoms/tree/hardening/save-system-v1)
- Default branch at review time: [main](https://github.com/areagleegy/AshenKingdoms/tree/main), head d1a727a0e3a2fc177136e1ed89f0e14e1992039c
- [Comparison: main → hardening/save-system-v1](https://github.com/areagleegy/AshenKingdoms/compare/main...hardening/save-system-v1)

The default scene, autoloads and rendering settings are configured in [project.godot](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/project.godot). This report prefers source scenes/scripts and snapshot-linked CI over older archive/PDF descriptions.

### Evidence vocabulary

| Label | Meaning |
|---|---|
| **Verified in source** | Directly observed in a referenced scene, script, resource, manifest or workflow |
| **CI reported** | A GitHub Actions run reports a result for a specific commit |
| **Documented limitation** | Stated in project docs and consistent with the inspected source |
| **Recommended** | Proposed next step, not claimed to exist already |
| **Not verified** | Requires execution, deployment, hardware or evidence unavailable to this review |

A repository file existing is not proof that a runtime scenario works. An automated smoke test is not an Internet security test, and a successful export is not proof of physical-device acceptance.

## 3. Project settings and high-level layout

### Godot project configuration

Observed settings:

- Engine feature version: 4.6; GDScript.
- Startup scene: res://scenes/ui/MainMenu.tscn.
- Autoloads:
  - DialogueManager → scripts/dialogue/dialogue_manager.gd
  - ContentManager → scripts/content/content_manager.gd
  - NetworkManager → scripts/core/network_manager.gd
- Rendering: gl_compatibility for desktop/mobile; ETC2/ASTC texture-compression import settings enabled.
- Content catalog URL and public key are empty by default. Production catalog delivery is therefore not configured by this snapshot.

### Top-level organization

    project.godot
    export_presets.cfg
    scenes/
      boot/Main.tscn
      debug/DebugOverlay.tscn
      network/MultiplayerArena.tscn
      network/NetworkAvatar.tscn
      network/NetworkEnemy.tscn
      npc/NPC.tscn
      ui/MainMenu.tscn
      ui/DialogueUI.tscn
      ui/ContentLibrary.tscn
      ui/VirtualJoystick.tscn
    scripts/
      components/          # Health and Inventory
      content/             # Catalog, download/install, asset loader
      core/                # Main, NetworkManager, quests, progression, save
      dialogue/            # Dialogue graph/model/actions/manager
      enemies/             # Offline RPG enemy
      items/               # Item resources and world pickups
      networking/          # Arena, network avatar and network enemy
      npc/
      player/
      ui/
    resources/
      dialogue/elder_intro.tres
      items/health_potion.tres
    assets/
      asset_manifest.json
      characters/player/README.md
      audio/, environments/, materials/, ui/, video/
    content/
      README.md
      catalog.example.json
    tests/
    tools/
    docs/
    .github/workflows/
      validate.yml
      build.yml

This is a scene-and-script design, not an ECS framework. Several gameplay nodes are constructed in script at startup rather than authored as complete .tscn subtrees. The definitive runtime hierarchy must therefore be read from both scene files and construction functions.

## 4. Scene trees and runtime composition

### 4.1 Main menu

Scene: [scenes/ui/MainMenu.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/ui/MainMenu.tscn)  
Controller: [scripts/ui/main_menu.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/ui/main_menu.gd)

    MainMenu (Control)
      [root script: main_menu.gd]
      Runtime-created UI:
        Background (ColorRect)
        CenterContainer
          PanelContainer
            VBoxContainer
              Title / subtitle / mode controls
              Single-player button
              Network host/join controls
              Address and port fields
              Status label

The .tscn itself contains only the root; buttons, panel and input fields are created in _build_ui(). Web builds disable the ENet host/join path in the menu controller.

### 4.2 Single-player root

Scene: [scenes/boot/Main.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/boot/Main.tscn)  
Runtime controller: [scripts/core/main.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/core/main.gd)

Authored scene tree:

    AshenKingdoms (Node3D, main.gd)
      DialogueUI (DialogueUI.tscn, CanvasLayer)
      ContentLibrary (ContentLibrary.tscn, CanvasLayer)
      DebugOverlay (DebugOverlay.tscn, CanvasLayer)

Runtime nodes created by main.gd:

    AshenKingdoms
      World (Node3D)
        WorldEnvironment
        Sun (DirectionalLight3D)
        Ground (StaticBody3D + CollisionShape3D)
        GroundVisual (MeshInstance3D)
        Player (CharacterBody3D, player.gd)
          CollisionShape3D
          Health (health.gd)
          Inventory (inventory.gd)
          InteractionDetector (Area3D, interaction_detector.gd)
          PlayerVisual / HeroFallbackVisual
        CameraPivot (Node3D, player_camera.gd)
          SpringArm3D
            Camera3D
        Enemies (Node3D)
          AshWraith_01..04 (CharacterBody3D, enemy.gd)
            CollisionShape3D + visual mesh(es)
            Health (health.gd)
        WanderingElder (instance of NPC.tscn)
      ProgressionManager (progression_manager.gd)
      QuestManager (quest_manager.gd)
      SaveSystem (save_system.gd)
      HUD (CanvasLayer, built by hud.gd)

The startup order is material: world and managers are constructed, then player, dialogue context, enemies/NPC and HUD. DialogueManager is configured with player/progression/quest references after player creation; it is not a second game root.

The player-art loader checks res://assets/characters/player/player.glb. That model is **not present in the reviewed asset tree**; code therefore uses a procedural low-poly fallback. Do not treat the directory or pipeline documentation as proof that the final character model has shipped.

### 4.3 Multiplayer arena

Scene: [scenes/network/MultiplayerArena.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/network/MultiplayerArena.tscn)  
Controller: [scripts/networking/multiplayer_arena.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/networking/multiplayer_arena.gd)

    MultiplayerArena (Node3D)
      Entities (Node3D)
        Peer_<peer_id> (NetworkAvatar instances, spawned at runtime)
        Enemy_<slot> (NetworkEnemy instances, spawned at runtime)
      EntitySpawner (MultiplayerSpawner)
        spawn_path = ../Entities

The arena dynamically builds its test ground/environment, simple landmarks, session HUD and touch controls. It configures MultiplayerSpawner with the avatar/enemy scenes and a custom spawn function accepting a small dictionary (player kind + peer ID, or enemy kind + slot). The server calls spawn(); peers receive replicated spawn/despawn operations.

### 4.4 Network avatar

Scene: [scenes/network/NetworkAvatar.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/network/NetworkAvatar.tscn)

    NetworkAvatar (CharacterBody3D, network_avatar.gd)
      CollisionShape3D
      VisualRoot (Node3D)
        BodyMesh (MeshInstance3D)
      CameraRig (Node3D)
        SpringArm3D
          Camera3D
      MultiplayerSynchronizer (SceneReplicationConfig)

The synchronizer's configured properties are position, rotation, velocity, current_health, max_health, level, experience, quest_progress, quest_completed and is_dead. Each is marked for initial spawn and replication. The script assigns multiplayer authority to peer 1 (server) for the avatar node, while owner_peer_id identifies which connected peer may submit input.

### 4.5 Network enemy

Scene: [scenes/network/NetworkEnemy.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/network/NetworkEnemy.tscn)

    NetworkEnemy (CharacterBody3D, network_enemy.gd)
      CollisionShape3D
      BodyMesh (MeshInstance3D)
      MultiplayerSynchronizer (SceneReplicationConfig)

Replicated fields are position, rotation, velocity, current_health, max_health, ai_state and is_dead. Enemy physics/AI runs on the server; client copies disable physics processing. AI is a simple direct-movement patrol/chase/attack/return state machine, not full navigation-mesh pathfinding.

### 4.6 NPC and UI support scenes

- scenes/npc/NPC.tscn: NPC CharacterBody3D, mesh, collision, TalkZone Area3D and Label3D prompt. Uses resources/dialogue/elder_intro.tres.
- scenes/ui/DialogueUI.tscn: CanvasLayer → hidden Panel → MarginContainer → VBoxContainer → speaker label, rich dialogue text, choices, continue hint and button.
- scenes/ui/ContentLibrary.tscn: CanvasLayer → open button and hidden panel, title/status, scrollable package list and refresh/close buttons.
- scenes/ui/VirtualJoystick.tscn: touch joystick Control.
- scenes/debug/DebugOverlay.tscn: diagnostic CanvasLayer and label.

Dynamic HUD/touch-control child trees are implemented in scripts and may not appear in the .tscn node listing.

## 5. Scene loading and startup flow

### Normal player startup

    Godot process
      -> project.godot run/main_scene
      -> MainMenu.tscn
      -> main_menu.gd builds menu UI
         -> Single player
              -> NetworkManager.leave_session()
              -> change_scene_to_file("res://scenes/boot/Main.tscn")
              -> main.gd registers input actions
              -> creates world and managers
              -> creates player/camera
              -> configures DialogueManager context
              -> creates offline enemies, NPC and HUD
              -> optionally loads save when --continue is present
              -> gameplay

Keyboard actions set in code include WASD/arrows, Space, Shift, I/Tab, Esc, F5, F9, E/Enter and left mouse attack. Mobile control is handled through touch-oriented UI/scripts; exact interaction should still be verified on a physical device.

### Host / dedicated server startup

    Godot process
      -> MainMenu.tscn / main_menu.gd
      -> detect --server, headless display or dedicated_server feature
      -> NetworkManager.start_host(port, max_clients)
      -> ENetMultiplayerPeer.create_server()
      -> defer scene change to MultiplayerArena.tscn
      -> configure MultiplayerSpawner
      -> mark host arena ready / spawn initial avatars and four enemies
      -> simulate authoritative state and replicate configured properties

Documented command:

    godot --headless --path . -- --server --server-port=7777

Default ENet UDP port is 7777. The headless menu path requests a 32-client configuration; ordinary hosting defaults to 8. These are settings, not proven capacity measurements.

### Client join

    MainMenu
      -> validate address and port
      -> NetworkManager.start_client(address, port)
      -> ENetMultiplayerPeer.create_client()
      -> wait for connection result (12-second timeout)
      -> on successful connection, change to MultiplayerArena
      -> client notifies server that the arena is ready
      -> server validates sender/connected peer/duplicate readiness
      -> server spawns client avatar and replicates arena entities

Disconnect handling resets the session to OfflineMultiplayerPeer, emits state signals and removes the relevant avatar on the server. Reconnect and host-failure scenarios still need broader end-to-end validation.

The old scripts/core/server.gd is a legacy/incomplete scaffold with a different default port; it is not the normal startup path configured by project.godot. Keep command-path documentation aligned with MainMenu.tscn and NetworkManager.

## 6. Multiplayer transport, authority and synchronization

### Transport and peer model

- Godot high-level multiplayer API over ENetMultiplayerPeer / UDP.
- Peer ID 1 is the server/host.
- NetworkManager is an autoload and owns host/client lifecycle, peer events, connection timeout and arena-ready signalling.
- MultiplayerSpawner is used for authoritative spawning of known arena entity scenes.
- MultiplayerSynchronizer replicates explicitly configured entity properties from the authority to connected peers.

Official references: [Godot 4.6 high-level multiplayer](https://docs.godotengine.org/en/4.6/tutorials/networking/high_level_multiplayer.html), [MultiplayerSpawner](https://docs.godotengine.org/en/4.6/classes/class_multiplayerspawner.html) and [MultiplayerSynchronizer](https://docs.godotengine.org/en/4.6/classes/class_multiplayersynchronizer.html).

### State ownership matrix

| State/action | Authority in this prototype | Client role |
|---|---|---|
| Local movement controls | Client produces movement intent; server simulates accepted movement | Capture input and send bounded intent |
| Avatar transform/velocity | Server simulation and replication authority | Render replicated position/rotation/velocity |
| Jump, gravity, speed | Server step | Request jump/sprint; no trusted coordinate writes |
| Player attack | Server checks cooldown, direction and range | Request attack; display replicated outcome |
| Enemy AI/navigation | Server | Display replicated enemy state |
| Health/damage/death/respawn | Server-only methods; state is replicated | Read state/display HUD |
| XP, level, kill quest | Server methods in the arena | Display replicated progression |
| Session peer membership | NetworkManager/Godot peer lifecycle; server spawns/removes avatars | Connect/disconnect and render state |
| Single-player save | Local player process | Write/read local save file |
| Persistent online progression | Not implemented | Must not be entrusted to a client-local file |

### Input and authoritative tick flow

The hardened avatar requests input at a nominal 50 ms interval (20 requests/second). Client input is sent to peer 1 via an unreliable RPC. Server-side validation checks:

1. RPC is being handled by the server.
2. Sender ID matches the avatar's configured owner_peer_id and is greater than 1.
3. Avatar is not dead.
4. The input token bucket permits the message.
5. Every direction component is finite; vector magnitude is bounded.
6. Vertical movement intent is discarded and horizontal intent normalized/clamped.

The server caches the request and applies gravity, jump, movement speed and turning in its physics step. If remote input becomes stale for 350 ms, requested movement/attack is cleared. Attacks are not client-authored damage values: the server enforces cooldown and selects an enemy by distance and forward direction, then calls its server-gated damage method. Enemy AI and enemy attacks likewise run on the server.

The hardened branch defines an input token bucket of 30 requests/second with a burst allowance of 60. Its network security regression test checks code constraints and consumes/refills the token bucket in a controlled test. This is meaningful protection for the movement RPC; it is **not** comprehensive rate limiting for every RPC or proof against Internet abuse.

### State replication

The avatar and enemy synchronizers publish a narrow set of gameplay properties. Spawns/despawns are managed by the arena spawner. Current scripts do not show a custom client prediction/reconciliation pipeline or explicit snapshot sequence numbers. Measure perceived latency and jitter before choosing whether interpolation, reconciliation or a fixed-tick snapshot model is warranted; do not add complexity without traces demonstrating the need.

### Network configuration

| Setting | Configured value | Interpretation |
|---|---:|---|
| ENet port | 7777 | Default port; UDP reachability/firewall rules still apply |
| Ordinary host max clients | 8 | API default |
| start_host() validation ceiling | 64 | Accepted configuration ceiling only |
| Headless startup max clients | 32 | Startup request only |
| Browser export | ENet controls disabled | Web multiplayer not implemented by this path |

**Capacity is unproven.** No configuration value in this table is a benchmark. Supportable capacity needs repeatable tests measuring CPU, memory, packet rates, tick duration and latency with representative devices and network conditions.

## 7. Persistence and save/load flow

The local save path is user://savegame.json; it is separate from online network state. The hardened branch's scripts/core/save_system.gd retains save_game(Dictionary) -> bool and load_game() -> Dictionary, and adds load_game_result() for diagnostics/recovery.

Save fields assembled by main.gd include a version marker, player position and health, level and experience, inventory, quest state and dialogue state. Inventory serialization/restore includes overflow-preservation behavior; a world pickup script exists on the hardening branch.

The hardened save flow is:

1. Serialize JSON and reject empty or over-1 MiB data.
2. Write and flush a temporary file.
3. Parse the temporary file and compare its bytes with the serialized content.
4. Refresh backup from an existing primary only if the primary is valid.
5. Stage the old primary before promoting the temporary save.
6. Attempt to restore the staged copy if promotion fails.
7. Load by checking primary, then staged copy, then backup, returning a status distinguishing missing from invalid/recovered data.

The save documentation explicitly avoids claiming a cross-platform atomic transaction or a guarantee that bytes have reached durable storage. Automated tests cover round-trip, backup recovery, oversized content, corrupt-primary handling, status reporting and deletion. This is local crash-recovery hardening, not an online account database, anti-cheat boundary or multiplayer persistence system.

## 8. Content and asset management

### Optional-content pipeline

Relevant scripts:

- scripts/content/content_catalog.gd — signed envelope and catalog schema validation.
- scripts/content/content_manager.gd — catalog fetch, download state, install registry, dependency/reference management.
- scripts/content/content_package_installer.gd — SHA-256 and file manifest validation, archive checks, staging and installation.
- scripts/content/content_asset_loader.gd — loads allowed assets from installed packages after integrity/path checks.
- tools/package_content.py and tools/sign_content_catalog.py — package/catalog tooling.

Intended lifecycle:

    Configure catalog URL + public verification key
      -> fetch catalog
      -> verify RSA-SHA256 signed envelope
      -> validate schema, IDs, versions, paths, dependencies and limits
      -> download package to a temporary .part file
      -> verify archive SHA-256 and expected file manifest
      -> reject unsafe paths/extensions/oversized contents
      -> extract into staging
      -> install under user://content/installed/<id>/<version>
      -> register installed package and load permitted GLB/audio resources

Catalog verification key and catalog URL are empty in project configuration, and the README says production download is disabled until a real catalog/CDN and signing configuration are set up. A sample catalog contains placeholder URLs and hashes; it is not a publishable production catalog. Private signing keys should never be stored in the repository, APK or CI logs.

Documented gaps include resumable downloads, version/update/rollback policy, interrupted-install recovery, low-storage/device testing and real hosted-package end-to-end tests. Package/file size bounds and path checks are present in source; the pipeline still needs tests against malicious/corrupt archives and an explicitly operated service.

### Asset and licensing status

The asset manifest requires source/license evidence and permissions for commercial use and redistribution. At this snapshot, assets/asset_manifest.json lists only assets/ashenkingdoms_icon.svg, authored in the project. No committed assets/characters/player/player.glb was found; the game has a procedural fallback. Empty or organizational asset directories and pipeline docs are not evidence of a finished character, environment, music, sound-effects or animation set.

Recommended per-asset metadata: asset path and type, author/source URL, license name/URL, attribution, redistribution/commercial permissions, modifications, and evidence/snapshot of the relevant license. Recheck original license terms, because “free download” does not automatically permit redistribution.

## 9. Platform architecture and release boundaries

| Platform | Code-supported path in this snapshot | Release blockers / boundaries |
|---|---|---|
| Desktop PC | Solo RPG prototype; experimental ENet host/client arena; headless arena startup | No production authentication, persistence backend, public hosting or measured scale |
| Android | Solo prototype, touch UI and experimental ENet arena; CI defines an ARM64 debug APK export | Physical-device acceptance, rendering/thermal/memory/touch tests, production signing and distribution setup |
| Web | HTML5 export and solo path | ENet host/join disabled; browser multiplayer requires a separate compatible transport and deployment design |

project.godot uses gl_compatibility for desktop/mobile and ETC2/ASTC texture-compression import settings. These are compatibility-oriented starting points, not proof of target-device frame rate or memory budgets. Test on reference hardware and measure before changing renderers, asset formats or quality settings.

Web multiplayer is not a flag switch: it needs browser-compatible transport, secure origin/HTTPS, server deployment and its own connect/disconnect/browser lifecycle test matrix.

## 10. Test tooling and current verification evidence

### Automated coverage visible in the workflow

.github/workflows/validate.yml defines import/parse, GDScript/scene loading, gameplay smoke and regression, player smoke, network-combat smoke, local ENet host/client loopback, content catalog/installer and Python package tests. The hardening branch also adds:

- tests/save_system_security_test.gd
- tests/network_rpc_security_test.gd
- tools/test_ci_security.py
- tools/run_local_qa.sh

The save regression suite tests specific file-recovery cases. The RPC regression suite covers selected input checks/token-bucket behavior, not an exhaustive simulation of malicious clients.

### Run status for the reviewed commit

- [Validate Godot Project — success](https://github.com/areagleegy/AshenKingdoms/actions/runs/39785781928), branch hardening/save-system-v1, SHA 0f117a3236e39cf1ed569d05915af3d440ea98b6.
- [Build Android and Web — skipped](https://github.com/areagleegy/AshenKingdoms/actions/runs/39785781880), same branch/SHA.

Therefore, **the checked evidence supports a successful validation workflow, not a successful Android/Web export on this exact snapshot**. Read results against the candidate SHA because CI varies across commits. No local Godot execution, real Android-device run, browser acceptance, Internet multiplayer test, load test or penetration test was performed during this repository inspection.

### Recommended verification sequence

1. Install Godot CLI 4.6 and Python 3; import/parse the project and load all GDScript/scenes in headless mode.
2. Run gameplay smoke/regression, player-character, network combat, RPC security, save security, content catalog/installer and Python package/signature suites.
3. Run bash tools/test-network-loopback.sh; record exact commit, Godot version, logs and outcome.
4. Build Android/Web and check workflow results on the same candidate commit; install APK on supported devices and test Web over HTTP/HTTPS in target browsers.
5. Test a host and separate client over the intended LAN/network. Include disconnects, host shutdown, malformed/non-finite movement input, invalid sender/target, replay, rate abuse, excess peers, packet loss/latency and repeated death/respawn.
6. Capture resource and performance measurements under representative load. Keep configured client count, tested capacity and production capacity as separate documented values.

See [docs/TEST_PLAN.md](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/docs/TEST_PLAN.md) and [docs/NETWORK_THREAT_MODEL_AR.md](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/docs/NETWORK_THREAT_MODEL_AR.md) for repository-defined test and threat-model details.

## 11. Prioritized architecture backlog

### P0 — before any public multiplayer deployment

- Specify a durable account/session identity, authentication and authorization model. ENet peer IDs are session IDs, not user authentication.
- Inventory every RPC and define per-peer rate limits, payload constraints, sender/ownership rules and replay/sequence policy. Movement input is hardened; not all RPC paths have comprehensive rate limiting.
- Keep inventory, rewards and progression authoritative; design separate server-side persistence before promising persistent online progress.
- Conduct two-device/LAN/internet-path testing, negative testing and resource/load measurement. Loopback success is not proof of Internet stability or security.
- Keep external hosting private/experimental until acceptance evidence and operational logging are ready.

### P1 — quality and stability

- Add traceable input/state diagnostics to measure tick delay, stale inputs, packet loss and state divergence before implementing prediction/reconciliation.
- Test host disconnect, abrupt process termination, reconnect, duplicate/late messages and session cleanup.
- Complete signed catalog/CDN setup only when a real service exists; test low storage, interruption, upgrade, rollback, corruption and package removal on Android.
- Define per-device frame-time, RAM, package-size and loading budgets; profile before adding heavier render/AI frameworks.

### P2 — content and product completion

- Add licensed, production-ready character/environment/animation/audio assets and validate the manifest for every redistributed asset.
- Add navigation/pathing only where environment tests show direct movement is insufficient.
- If Web multiplayer remains a release target, select and implement browser-compatible transport and server topology as a separate design/work package.

## 12. Key source files and references

| Concern | Source evidence |
|---|---|
| Engine settings and autoloads | [project.godot](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/project.godot) |
| Startup and mode routing | [MainMenu.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/ui/MainMenu.tscn), [main_menu.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/ui/main_menu.gd) |
| Solo runtime composition | [Main.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/boot/Main.tscn), [main.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/core/main.gd) |
| Network lifecycle | [network_manager.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/core/network_manager.gd) |
| Network spawn and arena | [MultiplayerArena.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/network/MultiplayerArena.tscn), [multiplayer_arena.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/networking/multiplayer_arena.gd) |
| Authoritative player state | [NetworkAvatar.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/network/NetworkAvatar.tscn), [network_avatar.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/networking/network_avatar.gd) |
| Authoritative enemy | [NetworkEnemy.tscn](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scenes/network/NetworkEnemy.tscn), [network_enemy.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/networking/network_enemy.gd) |
| Content and asset evidence | [content_catalog.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/content/content_catalog.gd), [content_package_installer.gd](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/scripts/content/content_package_installer.gd), [asset_manifest.json](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/assets/asset_manifest.json) |
| Validation workflow | [validate.yml](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/.github/workflows/validate.yml), [build.yml](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/.github/workflows/build.yml) |
| Networking and threat boundaries | [NETWORKING.md](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/docs/NETWORKING.md), [NETWORK_THREAT_MODEL_AR.md](https://github.com/areagleegy/AshenKingdoms/blob/0f117a3236e39cf1ed569d05915af3d440ea98b6/docs/NETWORK_THREAT_MODEL_AR.md) |

## Conclusion

The repository has a pragmatic prototype architecture: explicit Godot scenes, a small set of autoload services, separate offline and network gameplay paths, server-owned core arena simulation, explicit state replication and guarded content-install primitives. The best next move is incremental: complete release-evidence and security gates, not a broad framework rewrite. Prioritize server identity/authorization and RPC coverage before public hosting; measure performance before optimizing; and make the actual licensed asset package, not its directory layout, the source of truth for visual/audio completeness.
