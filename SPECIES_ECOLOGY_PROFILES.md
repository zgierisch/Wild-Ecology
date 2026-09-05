# Species Ecology Profiles

Species ecology is static biological data. It does not own temperament, learned
moves, relationships, current drives, runtime movement, or engine objects.

## Resolution

`SpeciesEcology.resolve(speciesId)` composes a fresh table in this order:

1. Conservative fallback
2. Selected ecological archetype
3. Species override

The resolver deep-copies tables, so callers may not mutate archetypes or species
definitions through a resolved result. Unknown species use the conservative
`solitary` fallback. A registered species must explicitly select a known
archetype.

Entity/runtime variation is applied by the owning consumer after resolution:

- `EcologyPhysiology` combines profile rates with `EcologicalPhenotype`.
- `CircadianSystem` persists individual phase and amplitude variation.
- `TraversalCapabilities` keeps profile biology, learned move semantics, and
  executable modes separate. `entity.ecology.locomotion` is a supported
  per-entity biological declaration override.
- `Fear` owns its existing entity-level fear/alarm overrides and uses the
  matching fear-archetype table.

Resolved profiles are never persisted. Persistent entities retain only genuine
individual state such as family, circadian variation, mechanics, temperament,
relationships, and memory.

## Fields

| Field | Type/range | Default | Current owner/consumer | Classification |
| --- | --- | --- | --- | --- |
| `archetype` | known string ID | `solitary` | resolver, Fear archetype lookup | biological baseline |
| `activityProfile` | known circadian ID | `FLEXIBLE` | `CircadianSystem` | biological baseline |
| `social.modifier` | number, 0-2 | `0.25` | Social exposure, flock search | species social baseline |
| `social.familyModifier` | number, 0-2 | `0.75` | Social exposure | species social baseline |
| `social.desiredGroupSize` | number, 1-12 | `1` | flock search | species social baseline |
| `physiology.thirstRate` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `physiology.hungerRate` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `physiology.fatigueRate` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `physiology.restRecovery` | number, 0.5-2 | `1` | live and dormant physiology | biological rate |
| `movement.wanderScale` | number, 0.5-1.5 | `1` | ambient wander after TARGET selection | physical pacing |
| `home.radius` | number, 1-5 | `2` | home-area establishment | biological area scale |
| `home.attachment` | number, 0.5-1.5 | `1` | RETURN_HOME utility context | biological attachment tendency |
| `home.roamingTolerance` | number, 1-6 | `2` | RETURN_HOME activation boundary | biological roaming tendency |
| `habitat` | ranked known string list | `GENERAL` | inspector; future habitat choice | declarative metadata |
| `restSites` | ranked known string list | `SHELTER`, `COVER` | rest-site resolver when a proven semantic mapping exists | biological preference |
| `concealmentSites` | array of known IDs | empty | rest-site resolver and concealment lifecycle | biological compatibility |
| `biologicalCapabilities` | known mode to boolean | `WALK=true` | `TraversalCapabilities` | biological declaration only |
| `feeding.acceptedOpportunityTypes` | array of known IDs | empty | food opportunity resolver | biological compatibility |
| `join` | threshold numbers, 0-100 | absent | voluntary-join threshold stub | partial future-phase rule |

Rest-site preference and concealment capability are separate. Current execution
uses only proven `TALL_GRASS` for species that explicitly accept it through
`concealmentSites`; legacy shelter, burrow, rocky, aquatic, cave, powered, and
elevated `restSites` remain declarative until trustworthy WorldSemantics exist.
`FLY`, `SWIM`, `CLIMB`, `TELEPORT`, and other biological declarations do not
grant runtime execution. WALK remains the only executable traversal mode.

Home parameters influence persistent area size and generic return pressure but
never issue behavior. Existing independence/boldness provide modest individual
variation after profile resolution. Static home parameters are not persisted;
the established individual `entity.home.area` is persistent schema-v8 ecology.

A social baseline never creates relationships. Relationship allocation still
requires observed interaction evidence through the relationship owners.

`TALL_GRASS_FORAGE` is currently the only supported feeding opportunity type.
It means bounded seed, insect, or vegetation-associated forage inferred from a
proven `TALL_GRASS` habitat cell; it does not mean every species eats grass.
Pidgey, Rattata, and Caterpie explicitly accept it. Aquatic, rocky, cave, and
construct profiles without a proven compatible resource retain HUNGER rather
than consuming inappropriate terrain.

## Adding A Species

Choose the closest existing archetype and add only meaningful biological
differences to `src/species/profiles.lua`:

```lua
ODDISH = {
  archetype = "sheltered_grazer",
  activityProfile = "NOCTURNAL",
  habitat = { "GROUND_COVER", "WOODLAND_EDGE" }
}
```

Do not repeat values already supplied by the archetype. Add a new archetype only
when several species need a coherent combination that existing archetypes
cannot express. Archetypes are flat compositional tables, not an inheritance
hierarchy.

Do not add personality fields. Curiosity, aggression, timidity, sociability,
and independence belong to individual generation and temperament. Do not add
raw stats or move IDs; those enter through `PokemonMechanicsAdapter` and
`MoveSemantics`.

## Validation And Inspection

All shipped definitions are validated when `SpeciesEcology` loads. Validation
rejects unknown archetypes, source fields, nested fields, activity profiles,
habitat/rest enums, capability names, malformed types, and out-of-range values.
Tests may call `SpeciesEcology.validateDefinitions(archetypes, profiles)` with
fixture tables.

Use `SpeciesEcology.inspect(speciesId)` for a compact resolved baseline. Use the
existing phenotype, circadian, and move-semantics inspectors for individual or
learned layers; those layers intentionally are not folded into the species
inspector.

Run focused checks with:

```powershell
& 'C:\Program Files\Lua\lua55.exe' tests\species_ecology_expansion_spec.lua
& 'C:\Program Files\Lua\lua55.exe' tests\mechanics_ecology_spec.lua
& 'C:\Program Files\Lua\lua55.exe' tests\circadian_spec.lua
& 'C:\Program Files\Lua\lua55.exe' tests\dormant_cohort_spec.lua
```
