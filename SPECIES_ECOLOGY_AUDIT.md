# Species Ecology and Mechanics Audit

## Scope

This is the portability and representative-profile foundation for Phase 9. It
does not claim exhaustive move semantics, complete species coverage, non-WALK
execution, or completion of Phase 9. The numbered implementation report below
contains exactly 118 findings and decisions.

## Implementation Report

1. Official Gen1Recomp `dev` source was audited before mechanics code was written.
2. The audited Pokemon instance is a plain serializable Lua table.
3. Its canonical species identity is a string key.
4. Its canonical move identity is a string key.
5. Its stored innate values are attack, defense, speed, and unified Special.
6. Each stored innate value is bounded by Gen I mechanics to 0 through 15.
7. HP innate potential is derived from the low bits of those four values.
8. The adapter reproduces that HP derivation inside the Gen I boundary.
9. Gen I stat development is stored separately for HP, attack, defense, speed, and Special.
10. The adapter normalizes nonlinear stat-development contribution instead of exposing raw accumulation.
11. Current calculated Gen I stats contain HP, attack, defense, speed, and unified Special.
12. Unified Special is projected to neutral specialAttack and specialDefense fields.
13. Both projected fields carry explicit shared-unified-Special provenance.
14. The neutral capability map reports that split Special is unavailable.
15. The neutral capability map reports that modern IV mechanics are unavailable.
16. The neutral capability map reports that modern EV mechanics are unavailable.
17. The neutral capability map reports that natures are unavailable.
18. The neutral capability map reports that abilities are unavailable.
19. The neutral capability map reports that gender is unavailable.
20. The neutral capability map reports that held items are unavailable.
21. The neutral capability map reports that move categories are not assumed.
22. Gen1Recomp move slots are normalized in their original order.
23. A normalized move includes its one-based slot.
24. A normalized move includes its canonical key.
25. A normalized move distinguishes known from currently usable.
26. Zero PP makes a move unusable without making it unknown.
27. Temporary disablement can make a move unusable without making it unknown.
28. PP Ups are applied with the audited Gen1Recomp maximum-PP formula.
29. Missing move registry metadata is represented explicitly as unavailable.
30. Missing metadata does not erase canonical move identity.
31. `mod.content.pokemon:get` is the supported merged species-data registry seam.
32. `mod.content.moves:get` is the supported merged move-data registry seam.
33. Current official `mod.game` is a public generation-resolving live-game seam.
34. Owned Pokemon may be resolved from a declared party index through the adapter only.
35. The adapter can also consume an injected canonical Pokemon table for tests and wild records.
36. No engine object is stored in a normalized snapshot.
37. No engine object is added to persistent Wild Ecology records.
38. Wild Ecology does not require a modified Gen1Recomp build.
39. Production adapter registration occurs during Wild Ecology module loading.
40. No production generation branch was added above the adapter.
41. The generic facade validates every registered adapter contract.
42. The generic facade has an explicit unavailable snapshot.
43. Missing mechanics data does not fabricate innate values or moves.
44. Snapshot callers receive defensive copies.
45. Caller mutation cannot corrupt a cached mechanics snapshot.
46. Mechanics signatures include the individual record fields relevant to phenotype and moves.
47. Option-dependent metadata is cached only with an explicit caller revision key.
48. Explicit invalidation is available for one entity or the whole facade cache.
49. A future mock adapter with a different innate range passes through the same facade.
50. A future mock adapter with split Special passes through the same facade.
51. A future mock adapter with a different internal move token layout reaches the same neutral shape.
52. Generic consumers do not inspect DVs.
53. Generic consumers do not inspect stat experience.
54. Generic consumers do not inspect Gen I calculated-stat layout.
55. Generic consumers do not inspect raw engine move slots.
56. MoveSemantics consumes only normalized move snapshots.
57. MoveSemantics recognizes a deliberately small proof vocabulary.
58. DIG declares BURROW and shelter-excavation semantics.
59. TELEPORT declares a teleport traversal semantic.
60. FLY declares an aerial traversal semantic.
61. SURF declares a swimming traversal semantic.
62. WHIRLWIND declares forced-displacement semantics.
63. ROAR declares forced-displacement and loud-signal semantics.
64. RECOVER declares self-recovery semantics.
65. FLASH declares illumination semantics.
66. MoveSemantics does not mutate PP.
67. MoveSemantics does not execute a move.
68. MoveSemantics does not choose a behavior state.
69. MoveSemantics does not alter personality.
70. Every semantic option separately reports known status.
71. Every semantic option separately reports current usability.
72. Every semantic option separately reports environmental possibility.
73. Every semantic option separately reports executor support.
74. An option is available only when all four gates permit it.
75. Learned traversal declarations remain inspectable even when not executable.
76. Biological traversal declarations remain separately inspectable.
77. Executor declarations remain separately inspectable.
78. WALK remains the only executable traversal mode.
79. TraversalEvaluator remains the final movement-legality authority.
80. NavigationPlanner remains generation-neutral.
81. WorldSemantics remains generation-neutral.
82. EcologicalPhenotype consumes only generation-neutral mechanics.
83. EcologicalPhenotype emits mobility.
84. EcologicalPhenotype emits endurance.
85. EcologicalPhenotype emits robustness.
86. EcologicalPhenotype emits physical power.
87. EcologicalPhenotype emits recovery capacity.
88. Every physical phenotype dimension is bounded to 0 through 1.
89. Missing mechanics produce an explicit neutral unavailable phenotype.
90. Relative-to-species values use a bounded transform rather than an absolute speed assumption.
91. Innate potential contributes modestly to physical phenotype.
92. Training development contributes modestly to physical phenotype.
93. Current relative physical capability remains the largest component.
94. Move-set differences do not alter phenotype.
95. Phenotype contains no aggression field.
96. Phenotype contains no curiosity field.
97. Phenotype contains no sociability field.
98. Phenotype contains no activity preference field.
99. Phenotype caching is keyed by mechanics signature.
100. SpeciesEcology resolves fallback, then archetype, then species override.
101. The conservative fallback is solitary, flexible, WALK-capable, and rate-neutral.
102. Archetype and species source tables are validated before use.
103. Physiology multipliers are bounded from 0.5 through 2.
104. Ambient wander scale is bounded from 0.5 through 1.5.
105. Social modifiers and desired group size are validated.
106. Unknown source fields, nested fields, archetypes, activity profiles, habitat/rest enums, and capability names are rejected.
107. Pidgey proves a diurnal flocking-bird override.
108. Rattata proves a nocturnal small-forager profile.
109. Spearow proves a second species sharing an archetype with distinct overrides.
110. Caterpie, Zubat, Geodude, Onix, Goldeen, Magikarp, Abra, and Magnemite broaden the representative set without species-specific controller logic.
111. Personality ranges, family pools, and sprite fallback remain outside SpeciesEcology.
112. Resolved species baselines are not copied into new persistent entities.
113. Save schema v8 strips copied species baselines, preserves v7 concealment, and adds only optional durable local home-area state.
114. Individual family and circadian variation remain persistent.
115. Live THIRST applies only the resolved species thirst multiplier.
116. Live FATIGUE and REST combine species rates with bounded endurance or recovery phenotype.
117. Dormant THIRST, FATIGUE, and REST use the same resolver and bounded phenotype formulas.
118. Ambient movement scale is consulted only after TARGET wandering is already selected.
119. Biological, learned, and executable traversal capabilities remain separate.
120. Rest-site rankings remain biological preference data; the current consumer executes only separately validated `TALL_GRASS` concealment where WorldSemantics proves it.
121. Home radius, attachment, and roaming tolerance are validated archetype/profile biology consumed by generic area establishment and RETURN_HOME utility; they never command behavior or persist as copied baselines.
122. Runtime observation, balancing, broader Gen I coverage, exhaustive move semantics, move execution, non-WALK traversal, and Phase 9 completion remain deferred.

## Verification

The focused adapter and mechanics/ecology contracts cover Gen I HP derivation,
unified Special, nonlinear development, PP Ups, defensive snapshots, future
adapter substitution, same-species physical differences, move/personality
non-interference, semantic gates, capability separation, fallback/profile
validation, representative profile composition, shared live/dormant physiology,
social sparsity, circadian routing, and bounded outputs. The full suite is run in isolated Lua
processes because adapter registration and several older tests mutate module
state.