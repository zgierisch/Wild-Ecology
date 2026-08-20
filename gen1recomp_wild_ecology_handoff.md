<!-- Converted from gen1recomp_wild_ecology_handoff.docx -->

# Wild Ecology

*Standalone Gen1Recomp mod for persistent wild Pokémon, natural behavior, social relationships, and voluntary joining*

**Design & Implementation Handoff**

*Prepared for continuation in GitHub Copilot*

| **Platform** | Gen1Recomp |
| --- | --- |
| **Target games** | Pokémon Red / Blue / Yellow (Gen I first) |
| **Mod posture** | Standalone; no hard dependency on another overworld-Pokémon mod |
| **Document status** | Working architecture and phased roadmap |

# Executive summary

Wild Ecology is a proposed standalone Gen1Recomp mechanic mod that replaces the abstract “random encounter only” model with persistent wild individuals that can appear visibly in the overworld, behave according to species and individual traits, form relationships with any entity they repeatedly encounter, and eventually choose to join a trainer voluntarily.

The central design rule is that the player is not given a special friendship subsystem. A Pokémon stores sparse relationship records toward entities it knows. The player is simply one entity among those possible relationship targets. The same values that explain why two Pokémon stay together, fear one another, or learn from one another also explain why a wild Pokémon may become comfortable around a trainer.

The mod must also provide its own visible wild-Pokémon spawning layer, because the base Gen I game does not populate routes with roaming wild Pokémon. Existing Overworld Encounters code is a useful reference for creating Gen1Recomp NPC objects and bridging them into battles, but Wild Ecology should not depend on that mod.

## Project goals

- Create persistent individual wild Pokémon with stable IDs, temperament, memory, and sparse entity-to-entity relationships.
- Populate each route or habitat from the vanilla encounter data while retaining a persistent local population between visits.
- Make wild Pokémon visible in the overworld as temporary avatars of persistent simulation entities.
- Replace generic wandering with state/utility-driven behavior: resting, foraging, drinking, fleeing, investigating, grouping, defending, and other natural actions.
- Allow social learning and group response: a Pokémon can react to the behavior of trusted associates toward a third entity.
- Provide a non-combat path to acquisition: sufficiently trusting and affiliative Pokémon may voluntarily join the trainer with guaranteed capture.
- Remain independently downloadable and functional without requiring a specific follower, voxel, weather, or overworld-spawn mod.
- Expose optional integration points so other mods can provide visuals, weather signals, followers, or other enhancements without becoming hard dependencies.

## Non-goals for the first implementation

- Do not implement all 151 species as bespoke AI.
- Do not begin with predator/prey combat, breeding, migration, or a complete ecosystem simulation.
- Do not require another mod to create the visible wild Pokémon.
- Do not build a separate class of “befriended” owned Pokémon. Voluntary joining should end in the ordinary owned-Pokémon pipeline.
- Do not optimize for Gen II until the Gen I vertical slice is stable.

# 1. Current technical context

## 1.1 What Gen1Recomp provides

The current Gen1Recomp mod guidance classifies new or changed battle/field mechanics as a MECHANIC mod, typically using the overhaul profile. The official mod tooling provides scaffold, validate, lint, tests, manifest/card conventions, scoped persistent storage through mod.storage, live game/world access through mod.game and mod.world, and inter-mod communication through mod.exports and mod.find().

The project documentation also makes an important compatibility distinction: mods should prefer the public API, and engine/mod-API changes require a separate RFC and parity process. For Wild Ecology, the first technical spike should determine whether visible NPC creation can be implemented entirely through the current public surface. If not, a temporary engine_internals implementation may be needed while documenting the missing public seam.

## 1.2 What the existing Overworld Encounters mod demonstrates

The current Gen1PC-OverworldEncounters repository demonstrates a working route from encounter data to visible overworld Pokémon. Its main.lua creates NPC objects, assigns a species sprite, sets generic WALK / ANY movement, places them on walkable or grass cells near the player, inserts them into overworld NPC/entity collections, and bridges collision into a wild battle.

Its current implementation treats those Pokémon as transient. The active wild objects live in a local activeWildNpcs table, are assigned a lifespan of roughly 35–50 seconds, and are removed when the lifespan expires or they get too far from the player. This is the specific architectural point Wild Ecology changes: the overworld NPC becomes a disposable avatar of a persistent animal, rather than the animal itself.

The reference mod currently requests the engine_internals permission. That is useful evidence that direct NPC creation works today, but it is not proof that the same operation is available through the preferred public API. Treat the repository as implementation reference code, not as a dependency or API contract.

## 1.3 Core architectural inversion

```text
REFERENCE-STYLE MODEL
roll encounter
    -> create NPC
    -> NPC exists for a short time
    -> remove NPC

WILD ECOLOGY MODEL
persistent individual
    -> selected for this map visit
    -> create temporary overworld avatar
    -> run perception / behavior / relationships
    -> destroy avatar when out of simulation range
    -> persistent individual remains
```

# 2. Design principles

**Entity-first, not player-first.** Social behavior is written against generic entity IDs. The player is one entity type, not a privileged relationship target.

**Persistent animal, temporary avatar.** Simulation state survives map transitions. The NPC/sprite/model that displays the animal can be reconstructed at any time.

**Species instinct + individual history + current context.** A Pokémon starts from species/archetype tendencies, then individual temperament and learned relationships modify its response.

**Sparse memory.** Only relationships formed through meaningful contact are stored. There is no all-to-all relationship matrix across Kanto.

**Behavior before animation.** Convincing timing, priorities, pauses, and reactions matter more than elaborate animation for the first releases.

**Parallel acquisition paths.** Traditional battle/catch remains valid. Relationship-based voluntary joining is an equally legitimate route, not a weaker substitute.

**Standalone first, integrations second.** The mod owns the minimum capabilities necessary to function alone. Other mods connect through optional adapters/exports.

# 3. Proposed architecture

## 3.1 Persistent entity record

Every persistent wild Pokémon gets a stable entity ID. The entity record should contain only long-lived state; renderer/NPC references must never be serialized.

```text
Entity {
    id                = "wild:route01:0007",
    kind              = "pokemon",
    species           = "PIDGEY",
    level             = 4,
    personalitySeed   = 847219,

    temperament = {
        boldness      = 0.30,
        sociability   = 0.75,
        curiosity     = 0.40,
        aggression    = 0.10,
        protectiveness= 0.25
    },

    home = {
        mapId         = "ROUTE_1",
        zoneId        = "south_grass"
    },

    relationships     = { ... },   -- sparse EntityID -> Relationship
    memory            = { ... },   -- limited significant events
    groupId           = nil
}
```

## 3.2 Relationship model

A relationship is directed. A may trust B more than B trusts A. The same structure is used Pokémon→Pokémon, Pokémon→player, and potentially Pokémon→NPC/trainer/follower entities.

| **Value** |** Meaning** |** Suggested range** |** Notes** |
| --- | --- | --- | --- |
| familiarity | Do I recognize this entity? | 0–100 | Rises through repeated exposure; decays slowly or not at all for significant relationships. |
| trust | Do I expect this entity to be safe/reliable? | 0–100 | Built by calm exposure and positive outcomes; damaged by threats/attacks. |
| affinity | Do I prefer being near this entity? | -100–100 | Drives association, following, companionship, and eventual voluntary joining. |
| threatMemory | How dangerous has this entity proven to be? | 0–100 | Longer-term learned wariness; distinct from immediate fear/stress. |
| hostility | Am I inclined to confront/drive off this entity? | 0–100 | Useful for territorial or rival relationships; not simply inverse trust. |

Immediate fear/stress should live in transient behavior state rather than the persistent relationship record. This prevents a momentary startle from becoming permanent memory unless an event explicitly updates threatMemory.

```text
relationships["player"] = {
    familiarity = 63,
    trust       = 48,
    affinity    = 17,
    threatMemory= 4,
    hostility   = 0,
    lastSeenTick= 183205,
    importance  = 0.42
}
```

## 3.3 Player representation

The behavior engine should see the player through the same entity interface as any other actor. The player may have unique capabilities (items, Poké Balls, commands, map transitions), but social evaluation should be generic.

```text
playerEntity = {
    id   = "player",
    kind = "trainer"
}

relationship = getRelationship(wildPokemonEntity, playerEntity)
```

## 3.4 Persistent route populations

Each wild area owns a persistent population pool derived from its normal encounter data. Only a subset of that pool is instantiated on a given visit. Repeatedly selecting the same IDs creates natural recurring encounters without forcing the exact same population to appear every time.

```text
Route 1 persistent pool (example capacity 20)

wild:route01:0001  PIDGEY
wild:route01:0002  RATTATA
wild:route01:0003  PIDGEY
...
wild:route01:0020  RATTATA

Visit A visible subset: 1, 3, 6, 11, 17, 20
Visit B visible subset: 2, 3, 8, 11, 15, 19

#0003 and #0011 recur as the same individuals.
```

Simply being selected again should not grant large relationship bonuses. Reappearance creates an opportunity for exposure; actual proximity, observation, interaction, and social learning should be the main sources of relationship change.

## 3.5 Overworld avatar layer

A persistent individual is instantiated into the current map as an overworld avatar. In an initial Gen1-only implementation this will likely be an NPC object with an entityId back-reference. The avatar is disposable; its persistent record is authoritative.

```text
PersistentEntity
      |
      v
AvatarFactory.spawn(entity, map, cell)
      |
      +-- NPC / entity object
      +-- entityId = persistent entity ID
      +-- display species
      +-- current cell / movement
      +-- transient state
      |
      v
AvatarFactory.despawn()
      |
      v
PersistentEntity remains in mod.storage
```

## 3.6 Perception and event layer

Behavior should respond to observations, not directly mutate player-specific values. A perception layer produces events that can update relationships and current state.

- NOTICE(entity): another entity enters perception.
- CALM_PROXIMITY(entity, duration): nearby exposure without hostile action.
- APPROACH(entity, speed/direction): possible threat or curiosity stimulus.
- ATTACK(entity, target): direct hostile evidence.
- FLEE(entity, from): social signal that a known associate perceives danger.
- REST / FORAGE / DRINK near entity: repeated peaceful co-presence.
- HELP / HEAL / FEED (later): explicit positive interactions.

## 3.7 Behavior controller

Use a small state machine or utility-scoring controller. Do not evaluate all possible behavior every rendered frame; update AI at a lower frequency and retain states for meaningful durations.

```text
candidate scores:
    flee threat entity          78
    remain near associate       61
    seek water                  44
    forage                      39
    rest                        22
    wander                      12

choose highest valid behavior, then apply hysteresis / cooldown
so the Pokémon does not change intent every update.
```

**Initial states:**

- IDLE
- WANDER
- FLEE
**Later states:**

- ALERT
- INVESTIGATE
- FOLLOW_ASSOCIATE
- FORAGE
- DRINK
- REST
- DEFEND
- CHASE
- RETURN_HOME
- SEEK_SHELTER

## 3.8 Social behavior and emergent grouping

Herding/flocking should be influenced by relationships rather than being only a scripted “herd mode.” A group ID may still be retained for efficient spawning and neighbor searches, but affinity/trust explain why individuals prefer proximity.

- Cohesion: move toward trusted/high-affinity associates when separated.
- Separation: avoid occupying/crowding the same cells.
- Alignment: weak preference to move in a similar direction as nearby associates.
- Social fear propagation: fear displayed by a trusted associate increases suspicion toward the apparent threat.
- Social reassurance: repeated calm interaction between a trusted associate and a third entity can slowly reduce wariness.

## 3.9 Environmental behavior

The map needs a lightweight semantic/environment query so behavior can distinguish useful locations instead of treating every walkable cell equally.

```text
Environment.getCellType(map, x, y) -> one or more tags

GRASS
PATH
WATER
WATER_EDGE
TREE_EDGE
ROCK
CAVE
SAND
FLOWER
LEDGE
SHELTER
...
```

Terrestrial Pokémon seeking water should target walkable cells adjacent to water, not the water cells themselves. Habitat preferences and needs can then score candidate destinations.

## 3.10 Species archetypes

Avoid 151 unique AI implementations. Build roughly 10–15 behavioral archetypes, then tune species parameters and exceptions.

- small skittish forager
- flocking bird
- herd grazer
- curious social animal
- territorial animal
- solitary predator
- ambush/hiding animal
- cave dweller
- shoreline animal
- aquatic animal
- insect/colony behavior
- stationary/plantlike
- large solitary animal
- supernatural/erratic

## 3.11 Voluntary joining

Voluntary joining is the endpoint of ordinary social variables, not a separate capture meter. When an individual has sufficiently high familiarity, trust, and affinity toward a trainer—and any species-specific prerequisites are met—it can choose to approach/follow and offer to join.

```text
if rel.familiarity >= join.familiarity
and rel.trust       >= join.trust
and rel.affinity    >= join.affinity
and rel.threatMemory <= join.maxThreat
and speciesRuleAllowsJoin(entity, trainer)
then
    entity.behavior = "WILLING_TO_JOIN"
end
```

The final acquisition should be guaranteed once the Pokémon chooses to join. The implementation should call the normal owned-Pokémon give/store path, then remove that persistent individual from the wild population. Traditional battle capture remains available.

# 4. Suggested project structure

```text
wild_ecology/
├── manifest.json
├── main.lua
├── mod.card
├── README.md
├── CHANGELOG.md
├── src/
│   ├── core/
│   │   ├── ids.lua
│   │   ├── save.lua
│   │   └── config.lua
│   ├── entities/
│   │   ├── entity.lua
│   │   ├── relationships.lua
│   │   └── memory.lua
│   ├── population/
│   │   ├── generator.lua
│   │   ├── manager.lua
│   │   └── selection.lua
│   ├── world/
│   │   ├── avatar_factory.lua
│   │   ├── spawn_cells.lua
│   │   ├── environment.lua
│   │   └── perception.lua
│   ├── behavior/
│   │   ├── controller.lua
│   │   ├── utility.lua
│   │   ├── social.lua
│   │   └── states/
│   │       ├── idle.lua
│   │       ├── wander.lua
│   │       ├── flee.lua
│   │       └── ...
│   ├── species/
│   │   ├── archetypes.lua
│   │   └── profiles.lua
│   ├── interaction/
│   │   ├── battle_bridge.lua
│   │   └── voluntary_join.lua
│   └── compat/
│       └── exports.lua
└── tests/
    ├── persistence_spec.lua
    ├── relationships_spec.lua
    ├── population_spec.lua
    └── behavior_spec.lua
```

# 5. Development roadmap

The roadmap is intentionally ordered to prove architecture before content. Each phase should leave a testable, working build.

| **Phase** |** Goal** |** Deliverable** |** Do not add yet** |
| --- | --- | --- | --- |
| 0 — Technical spike | Prove standalone wild avatar creation and persistence access. | One hard-coded Pidgey can appear on one test route; determine public API vs engine_internals requirement. | Population generation, relationships, ecology. |
| 1 — Persistent individual | Separate simulated animal from overworld NPC. | Stable entity ID survives leaving/re-entering map; avatar reconstructs from stored entity. | All species; catch mechanics. |
| 2 — Basic relationship behavior | Prove generic entity-to-entity memory. | Pidgey tracks familiarity/trust toward player and another Pokémon; flee behavior changes with relationship. | Affinity, herding, needs. |
| 3 — Persistent route population | Generate local population from vanilla encounter data. | Route pool of persistent IDs; random visible subset each visit; recurring animals are the same records. | Complex habitat logic. |
| 4 — Social behavior | Make relationships affect Pokémon-to-Pokémon behavior. | Loose grouping, social fear propagation, reassurance, association/following. | Predator/prey combat. |
| 5 — Environmental ecology | Add needs and habitat attraction. | Resting, foraging, water-seeking, home/territory, reduced constant wandering. | Full Kanto tuning. |
| 6 — Species profiles | Scale behavior without 151 custom AIs. | Archetypes + species parameters; representative test species across habitats. | One-off polish for every species. |
| 7 — Affinity & voluntary joining | Provide passive acquisition path. | High-trust/high-affinity Pokémon can choose to follow and join; guaranteed final capture into normal party/box. | Legendary edge cases beyond minimal rules. |
| 8 — Compatibility & performance | Make it distributable and cooperative. | Exports API, optional adapters, simulation LOD, migration/versioning, documented incompatibilities. | Gen II claim until tested. |

## 5.1 Phase 0: technical spike — first work for Copilot

1. Scaffold a new standalone overhaul-profile mod with category MECHANIC and Gen I targeting.
1. Create a single test route condition (Route 1 is fine) and a hard-coded persistent entity record for one Pidgey.
1. Determine the preferred current method to instantiate a visible NPC through mod.world/public APIs. Search current Gen1Recomp source/docs before copying private-engine requires.
1. If no supported public spawn seam exists, implement the smallest engine_internals prototype and isolate it behind AvatarFactory so it can be replaced later.
1. Assign the runtime NPC an entityId field linking it to the persistent record.
1. Use mod.storage for a tiny save payload: entity ID, species, level, and one numeric relationship field.
1. Leave the route and return; verify the same entity record is reconstructed.
1. Add a headless/unit test for serialization logic even if avatar creation itself requires an in-game integration test.

## 5.2 Phase 1 success test

```text
Test case: persistent Pidgey

1. Enter Route 1.
2. Wild Ecology creates Pidgey entity wild:route01:0001.
3. Avatar appears visibly in overworld.
4. Entity receives familiarity[player] = 12.
5. Leave Route 1.
6. Runtime NPC is destroyed.
7. Re-enter Route 1.
8. wild:route01:0001 is loaded from storage.
9. A new runtime avatar is created for that same ID.
10. familiarity[player] is still 12.

PASS: persistent animal identity is independent of the runtime NPC.
```

## 5.3 Version 0.1 definition of done

- Standalone install: no other mod required.
- One test route contains several persistent wild Pokémon with stable IDs.
- Visible avatars can be spawned/despawned without losing persistent state.
- Each individual has deterministic temperament generated from a seed.
- Relationships are generic sparse EntityID→Relationship records.
- At least Pokémon→player and Pokémon→Pokémon relationships are demonstrated.
- Initial states are IDLE, WANDER, and FLEE.
- Repeated calm exposure changes familiarity/trust and visibly changes flee behavior.
- Leaving and returning preserves the population and relationships.
- No voluntary joining yet; no environmental needs yet.
- modkit validate/lint and project tests pass for the supported Gen I target.

# 6. Initial behavior and relationship rules

These values are placeholders for tuning, not canonical balance. The important point is that updates are event-driven and accept generic observer/subject IDs.

| **Event** |** Familiarity** |** Trust / threat** |** Notes** |
| --- | --- | --- | --- |
| Notices entity | +1 | none | Create sparse relationship entry if absent. |
| Calm proximity for sustained interval | +1 | trust +0.5; threatMemory -0.1 | Rate-limit; do not reward map-transition farming. |
| Entity approaches quickly/directly | +0.5 | transient fear +; trust -0.5 if repeated | Temperament modifies interpretation. |
| Direct attack | +2 | trust -10; threatMemory +15; hostility may + | Strong durable evidence. |
| Trusted associate flees from entity | +1 | threatMemory toward apparent threat + small amount | Social learning. |
| Trusted associate remains calm near entity | +1 | trust toward entity + small amount | Social reassurance. |

## 6.1 Anti-farming rule

Map reloads alone must not rapidly create trust. Passive familiarity can receive a tiny, cooldown-limited contribution from recurring presence, but trust and affinity should primarily arise from observed behavior and interaction.

## 6.2 Individual variation

A personalitySeed should deterministically perturb species defaults. Two Rattata should usually resemble one another but need not have identical boldness or social responses.

```text
species default fearfulness = 0.75

individualFearfulness =
    clamp(speciesDefault * seededRandom(0.80, 1.20), 0, 1)
```

# 7. Persistence and save data

Use mod.storage rather than raw filesystem writes. Save only persistent simulation data. Never serialize runtime NPC references, map controller objects, textures, functions, or other engine objects.

```text
save = {
    schemaVersion = 1,
    nextEntitySerial = 21,

    populations = {
        ROUTE_1 = {
            members = {
                ["wild:route01:0001"] = { ... },
                ["wild:route01:0002"] = { ... }
            }
        }
    }
}
```

## 7.1 Sparse relationship storage

- Do not preallocate relationships between every pair of persistent Pokémon.
- Create a record only after meaningful contact or social observation.
- Track last interaction / importance so low-value relationships can decay or be pruned.
- Keep close associates, persistent threats, and trainer relationships longer.
- Use versioned save schemas and migrations before public releases that change structure.

# 8. Performance model

The simulation should be local and low-frequency. A route may have dozens of persistent residents, but only a handful need full runtime avatars and frequent AI updates near the player.

```text
Suggested simulation levels

near player:
    visible avatar
    full perception + behavior ticks

farther on current map:
    visible/optional avatar
    reduced-frequency behavior

outside active map:
    no NPC
    persistent record only
    optional coarse time advancement later
```

- Use spatial buckets or a short nearby-entity list instead of comparing every entity with every other entity.
- Evaluate behavior perhaps a few times per second, not every render frame.
- Use state duration/hysteresis to reduce pathfinding and prevent jitter.
- Cache environment tags for a map rather than repeatedly classifying every cell.
- Begin with small visible counts comparable to existing overworld-spawn mods, then profile before increasing density.

# 9. Standalone mod and compatibility strategy

Wild Ecology must work when it is the only installed gameplay mod. It should therefore own the minimum spawn/avatar, population, behavior, relationship, and voluntary-join systems itself.

## 9.1 No hard dependency on Overworld Encounters

Do not attach Wild Ecology to the private activeWildNpcs table or other implementation details of Gen1PC-OverworldEncounters. That repository is reference code. Two independent wild-spawn mods will likely conflict if enabled together until an explicit adapter or disable-one-spawner compatibility mode is developed.

## 9.2 Optional public exports

Once the core is stable, expose a narrow API through mod.exports so compatible mods can query or extend behavior without direct access to internal tables.

```text
Possible exports (later)

getEntity(entityId)
getVisibleWildEntities()
getRelationship(sourceId, targetId)
notifyInteraction(event)
registerVisualProvider(provider)
registerEnvironmentSignalProvider(provider)
registerBehaviorModifier(provider)
```

The exact export surface should be conservative. Avoid exposing mutable internal tables; return copies/read-only views or specific methods.

# 10. Testing plan

## 10.1 Unit/headless tests

- Stable ID generation and deterministic temperament from personalitySeed.
- Relationship creation is sparse and directional.
- Relationship serialization/deserialization preserves values.
- Population selection returns existing IDs rather than creating new individuals every visit.
- Captured/joined entity is removed from the wild population exactly once.
- Utility/state logic chooses FLEE for a high-threat unfamiliar entity and does not for a trusted entity.
- Social learning updates relationships toward a third entity only under defined observation conditions.
- Save schema migration tests once schemaVersion > 1.

## 10.2 In-game integration tests

- NPC/avatar spawn and despawn on a real map.
- Map transition reconstructs the same persistent individual.
- Collision and battle bridge uses the correct species/level/identity.
- Wild avatars do not block required scripted paths or spawn on occupied/invalid cells.
- Behavior remains stable during menus, battles, warps, cutscenes, and map changes.
- Mod disabled = vanilla behavior unchanged.
- Mod installed alone = useful first-run behavior and no missing dependency errors.

# 11. Open technical/design questions

**Public NPC creation seam:** Can the current public mod API create/insert NPC entities cleanly, or is engine_internals presently required? This is Phase 0’s first research task.

**Avatar art source:** What distributable/legal overworld sprite source should the standalone mod ship or generate? Keep the visual provider abstract so this can change.

**Vanilla encounter suppression:** Should ordinary random encounters remain active alongside visible populations, or should the mod suppress grass encounters and route encounters through visible individuals? Decide after the vertical slice.

**Population regeneration:** When and why should persistent residents die, migrate, evolve, or be replenished? For 0.1, replenish only when an entity is captured/removed and keep rules simple.

**Battle persistence:** If a persistent individual is battled but not captured, should HP/status persist after battle? The architecture permits it, but this can be deferred.

**Legendary/static Pokémon:** Treat static/legendary encounters separately from ordinary route population until the basic system is stable.

**Trust visibility:** Prefer behavioral cues over a visible meter, but debug builds should expose relationship values for tuning.

**Time:** Decide later whether needs and relationship decay use real time, game time, map ticks, or a hybrid.

# 12. GitHub Copilot handoff

Copilot should treat this document as the architecture specification, but verify current Gen1Recomp APIs against the repository before writing engine-facing code. In particular, do not assume code copied from Overworld Encounters represents the preferred current API.

## 12.1 First prompt / task sequence

1. Inspect the current Gen1Recomp mod documentation and relevant world/NPC APIs. Report the supported method for creating a runtime NPC from a mod and whether engine_internals is required.

2. Scaffold a standalone Gen I overhaul-profile MECHANIC mod named wild_ecology (working ID; rename if needed).

3. Implement src/entities/entity.lua and src/entities/relationships.lua as engine-independent Lua modules with tests.

4. Implement versioned storage helpers and one hard-coded Route 1 Pidgey record.

5. Implement AvatarFactory behind a single interface. Do not leak NPC engine types into the persistent entity modules.

6. Spawn the Pidgey, attach entityId, despawn on map exit, reconstruct on return.

7. Only after persistence passes, add generic perception and IDLE/WANDER/FLEE.

## 12.2 Architectural invariants Copilot should not violate

- Never add trustWithPlayer or affinityWithPlayer fields to a Pokémon record.
- Never make the runtime NPC object the authoritative Pokémon identity.
- Never create a full relationship matrix for all entities.
- Never make Overworld Encounters a hard dependency.
- Never serialize engine runtime objects.
- Never create a second owned-Pokémon format for voluntary captures.
- Never tune all 151 species before the vertical slice is demonstrated.
- Keep engine-facing code isolated behind adapters/factories so public API changes are survivable.

# 13. Sources and reference repositories

Sources were checked on August 19, 2026. Official Gen1Recomp documentation is authoritative for the mod platform. Gen1PC-OverworldEncounters is cited as a community reference implementation, not as an API specification.

**S1 — Gen1Recomp repository**

Official project repository. [https://github.com/bryanthaboi/gen1recomp](https://github.com/bryanthaboi/gen1recomp)

**S2 — Gen1Recomp CONTRIBUTING-mods.md (dev)**

Official mod-platform guidance: scaffold profiles, MECHANIC category, validation/tests, mod.world, mod.storage, sandboxing, mod.exports/mod.find, and public-API expectations. [https://github.com/bryanthaboi/gen1recomp/blob/dev/CONTRIBUTING-mods.md](https://github.com/bryanthaboi/gen1recomp/blob/dev/CONTRIBUTING-mods.md)

**S3 — Gen1PC-OverworldEncounters repository**

Community project that replaces invisible encounters with visible roaming overworld Pokémon; useful comparison/reference. [https://github.com/gamecorner-033/Gen1PC-OverworldEncounters](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters)

**S4 — Overworld Encounters README**

Describes visible roaming wild Pokémon, direct overworld catching, combat, alert/flee behavior, and follower compatibility. [https://github.com/gamecorner-033/Gen1PC-OverworldEncounters/blob/main/README.md](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters/blob/main/README.md)

**S5 — Overworld Encounters main.lua**

Reference implementation showing NPC creation, generic WALK movement, spawn-cell selection, activeWildNpcs management, lifespan/despawn logic, and battle bridge. [https://github.com/gamecorner-033/Gen1PC-OverworldEncounters/blob/main/main.lua](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters/blob/main/main.lua)

**S6 — Overworld Encounters manifest.json**

Shows the current community mod requests engine_internals; useful warning not to assume its internal approach is the preferred public API. [https://github.com/gamecorner-033/Gen1PC-OverworldEncounters/blob/main/manifest.json](https://github.com/gamecorner-033/Gen1PC-OverworldEncounters/blob/main/manifest.json)

## Source-derived implementation facts used in this document

- [S2] Gen1Recomp’s mod tooling supports content, overhaul, and total_conversion scaffold profiles; MECHANIC is the category for new/changed field or battle mechanics and typically maps to overhaul.
- [S2] New code is directed to use mod.world for the live world, mod.storage for persistent mod data, and mod.exports/mod.find for inter-mod communication.
- [S2] The official guide prefers public mod API seams; engine/mod-API changes belong to a separate RFC/parity process.
- [S4] The community Overworld Encounters mod exists specifically to replace invisible random encounters with visible roaming wild Pokémon.
- [S5] Its current main.lua creates NPCs with movement='WALK' and range='ANY', inserts them into overworld NPC/entity collections, and stores active runtime objects in activeWildNpcs.
- [S5] Those runtime objects are currently transient, with a roughly 35–50 second lifespan and distance-based removal.
- [S6] The current manifest requests engine_internals, so Wild Ecology must verify the supported spawn path rather than assuming this implementation is public API.

# 14. One-paragraph project brief

Build Wild Ecology as a standalone Gen1Recomp MECHANIC mod that creates visible wild Pokémon from persistent local populations instead of disposable random spawns. Each wild Pokémon has a stable ID, deterministic temperament, needs, and sparse directed relationships with entities it has encountered. The player is simply a trainer entity in that same system. Behavior combines species instinct, individual temperament, learned relationships, and current context to produce fleeing, resting, grouping, environmental attraction, and social learning. Repeated positive interaction can raise familiarity, trust, and affinity until a Pokémon voluntarily follows and joins the trainer through a guaranteed normal capture without combat. The mod must function alone, use other mods only through optional APIs, and be developed in vertical slices beginning with one persistent visible Pidgey on one route.
