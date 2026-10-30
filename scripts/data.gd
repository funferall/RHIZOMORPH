extends RefCounted
# Every tunable number in RHIZOMORPH lives here: board layout, factions,
# structures, units, tech trees and spore actions.

const HALF_W := 48.0
const HALF_D := 36.0
const SIM_RES := 4            # GPU mycelium cells per world unit
const SIM_W := 384
const SIM_H := 288
const COARSE_W := 96          # 1 cell per world unit, read back to the CPU
const COARSE_H := 72

const POP_CAP := 40
const BASE_LINK := 14.0       # how far a rhizomorph cord can reach
const CORD_REGROW := 12.0     # seconds before a severed cord regrows
const NUTRIENT_RATE := 0.013  # income per (density * nutrient) per coarse cell per second
const SUGAR_SCALE := 0.3      # a tree's "sugar" * this = sugar/s split between all mantles on it
const START_RES := [300.0, 0.0, 30.0]   # nutrients, sugar, spores
const SPORE_CAP := 100.0
const CORD_HP := 90.0
const STARVE_DPS := 0.012     # fraction of max hp lost per second by a cut-off structure
const AGGRO := 9.0            # how far idle units notice enemies
const CAST_RANGE := 16.0      # spore actions land within this of your units / structures

const START_POS := [Vector2(-34, 21), Vector2(34, 21), Vector2(0, -25)]

const TREES := [
	{"name": "Old Oak", "pos": Vector2(0, 1), "radius": 3.0, "roots": 15.0, "sugar": 6.0, "kind": "oak"},
	{"name": "Birch", "pos": Vector2(-21, -9), "radius": 1.6, "roots": 10.0, "sugar": 3.0, "kind": "birch"},
	{"name": "Birch", "pos": Vector2(21, -9), "radius": 1.6, "roots": 10.0, "sugar": 3.0, "kind": "birch"},
	{"name": "Hemlock", "pos": Vector2(0, 25), "radius": 2.0, "roots": 11.0, "sugar": 3.5, "kind": "hemlock"},
]
const MANTLES_PER_TREE := 3

const ROCKS := [
	[Vector2(-41, -27), 6.0, 3.2], [Vector2(42, -29), 5.0, 2.6], [Vector2(21, 31), 3.4, 1.6],
	[Vector2(-20, 32), 3.0, 1.4], [Vector2(9, -13), 2.6, 1.3], [Vector2(-44, 4), 3.0, 1.8],
	[Vector2(45, 6), 3.2, 1.6], [Vector2(-10, 17), 2.0, 0.9],
]
const PUDDLES := [
	[Vector2(-12, 11), 4.4], [Vector2(13, 13), 3.6], [Vector2(-15, -19), 3.2], [Vector2(38, -6), 3.0], [Vector2(-38, -10), 2.6],
]
const LOGS := [
	[Vector2(12, -35), Vector2(44, -15), 1.7],
	[Vector2(-46, 30), Vector2(-28, 34), 1.1],
]

const FACTIONS := [
	{
		"key": "amanita", "name": "Amanita Court", "color": Color(0.92, 0.18, 0.12),
		"motto": "Toxins and rings. Every bite poisons.",
		"heart": "heart_amanita",
		"build": ["node", "mantle", "agaric_ring", "clathrus_cage", "deathcap_grove", "lantern", "bracket"],
		"abilities": ["haze", "fairy_ring", "bloom"],
		"techs": ["exoenzymes", "spore_sacs", "bootlaces", "phalloides", "universal_veil"],
		"decor": ["agaric_button", "mycena_white"],
	},
	{
		"key": "morel", "name": "Morel Hollow", "color": Color(0.98, 0.8, 0.22),
		"motto": "Thick-walled, regrowing, born from fire.",
		"heart": "heart_morel",
		"build": ["node", "mantle", "morel_patch", "earthstar", "cordyceps_spire", "lantern", "bracket"],
		"abilities": ["volley", "zombify", "wildfire"],
		"techs": ["exoenzymes", "spore_sacs", "bootlaces", "hypocreales", "pyrophilous"],
		"decor": ["morel_small", "elf_cup_small"],
	},
	{
		"key": "veiled", "name": "Veiled Choir", "color": Color(0.74, 0.46, 1.0),
		"motto": "Stench, speed and spore artillery.",
		"heart": "heart_veiled",
		"build": ["node", "mantle", "veil_hall", "birds_nest", "pilobolus_bed", "lantern", "bracket"],
		"abilities": ["lure", "barrage", "giant_puffball"],
		"techs": ["exoenzymes", "spore_sacs", "bootlaces", "pilobolus", "calvatia"],
		"decor": ["puffball_small", "inkcap"],
	},
]

const BUILD_KEYS := ["N", "M", "B", "T", "G", "L", "K"]

# radius: footprint / click radius. myc: radius of mycelium this structure feeds.
const STRUCTURES := {
	"heart_amanita": {"name": "Sclerotium of the Court", "species": "giant_agaric", "hp": 2400, "radius": 3.6, "myc": 15.0, "spores": 0.55, "nutrients": 2.0, "trains": [], "research": true,
		"desc": "Your Heart. Researches lineages. If it falls, the Court rots."},
	"heart_morel": {"name": "Sclerotium of the Hollow", "species": "giant_morel", "hp": 2700, "radius": 3.6, "myc": 15.0, "spores": 0.55, "nutrients": 2.0, "trains": [], "research": true,
		"desc": "Your Heart. Researches lineages. If it falls, the Hollow rots."},
	"heart_veiled": {"name": "Sclerotium of the Choir", "species": "giant_veiled", "hp": 2300, "radius": 3.6, "myc": 15.0, "spores": 0.6, "nutrients": 3.5, "trains": [], "research": true,
		"desc": "Your Heart. Researches lineages. If it falls, the Choir rots."},
	"node": {"name": "Armillaria Node", "species": "armillaria", "cost": [55, 0], "hp": 320, "build": 7.0, "radius": 1.6, "myc": 9.5,
		"desc": "Honey-fungus rhizomorph hub. Cheap. Pushes your mycelium outward and relays supply."},
	"mantle": {"name": "Chanterelle Mantle", "species": "chanterelle", "cost": [80, 0], "hp": 360, "build": 9.0, "radius": 1.6, "myc": 6.0, "near_tree": true,
		"desc": "Ectomycorrhizal sheath on tree roots. Trades minerals for SUGAR. Must be in a tree's root zone; the tree's sugar is shared between every mantle on it."},
	"lantern": {"name": "Mycena Lantern", "species": "mycena_lantern", "cost": [70, 20], "hp": 260, "build": 9.0, "radius": 1.4, "myc": 5.0, "spores": 0.5, "req": "spore_sacs",
		"desc": "Bioluminescent Mycena colony. +0.5 spores/s."},
	"bracket": {"name": "Ganoderma Bracket", "species": "bracket", "cost": [90, 0], "hp": 500, "build": 10.0, "radius": 1.8, "myc": 6.0, "near_trunk": true, "nutrients": 1.6, "req": "exoenzymes",
		"desc": "Wood-rotting shelf on a trunk base. +1.6 nutrients/s straight from the heartwood."},

	"agaric_ring": {"name": "Fly Agaric Ring", "species": "fly_agaric", "cost": [120, 0], "hp": 650, "build": 11.0, "radius": 2.4, "myc": 7.0, "spores": 0.15, "trains": ["wartling", "spitter"],
		"desc": "Fruiting body. Trains Wartlings and Muscarine Spitters."},
	"clathrus_cage": {"name": "Clathrus Cage", "species": "clathrus", "cost": [100, 0], "hp": 520, "build": 10.0, "radius": 1.8, "myc": 5.0,
		"attack": {"dmg": 11, "range": 9.5, "cd": 0.9, "slow": 0.45, "slow_t": 2.0, "shot": "spit"},
		"desc": "Red latticed stinkhorn tower. Its slime slows what it hits."},
	"deathcap_grove": {"name": "Death Cap Grove", "species": "death_cap", "cost": [150, 70], "hp": 700, "build": 14.0, "radius": 2.4, "myc": 7.0, "trains": ["angel"], "req": "phalloides",
		"desc": "Amanita phalloides colony. Trains Destroying Angels."},

	"morel_patch": {"name": "Morel Patch", "species": "morel", "cost": [120, 0], "hp": 760, "build": 11.0, "radius": 2.4, "myc": 7.0, "spores": 0.15, "trains": ["bruiser", "slinger"],
		"desc": "Fruiting body. Trains Morel Bruisers and Elf-Cup Slingers."},
	"earthstar": {"name": "Earthstar", "species": "earthstar", "cost": [100, 0], "hp": 600, "build": 10.0, "radius": 1.8, "myc": 5.0,
		"attack": {"dmg": 15, "range": 7.5, "cd": 1.3, "splash": 2.6, "shot": "puff"},
		"desc": "Geastrum tower. Bellows clouds of spores that hit everything nearby."},
	"cordyceps_spire": {"name": "Cordyceps Spire", "species": "cordyceps", "cost": [150, 70], "hp": 700, "build": 14.0, "radius": 2.2, "myc": 7.0, "trains": ["stalker"], "req": "hypocreales",
		"desc": "Parasitic Hypocreales. Trains Cordyceps Stalkers."},

	"veil_hall": {"name": "Veiled Lady Hall", "species": "veiled_lady", "cost": [115, 0], "hp": 700, "build": 10.0, "radius": 2.4, "myc": 7.0, "spores": 0.15, "trains": ["lure_fly", "bomber"],
		"desc": "Fruiting body. Trains Fly-Lures and Puffball Bombers."},
	"birds_nest": {"name": "Bird's Nest", "species": "birds_nest", "cost": [110, 0], "hp": 480, "build": 10.0, "radius": 1.8, "myc": 5.0,
		"attack": {"dmg": 22, "range": 13.0, "cd": 2.4, "splash": 2.2, "shot": "egg", "arc": true},
		"desc": "Cyathus splash-cup artillery. Long range, lobs peridioles."},
	"pilobolus_bed": {"name": "Pilobolus Bed", "species": "pilobolus", "cost": [150, 70], "hp": 560, "build": 14.0, "radius": 2.2, "myc": 7.0, "trains": ["sniper"], "req": "pilobolus",
		"desc": "Hat-throwers. Trains Pilobolus Snipers."},
}

const UNITS := {
	"wartling": {"name": "Wartling", "species": "u_wartling", "cost": [30, 0], "hp": 100, "dmg": 10, "range": 1.3, "cd": 0.75, "speed": 6.2, "train": 4.5, "poison": 3.0, "shot": "",
		"desc": "Warty melee sporeling. Poisons on hit."},
	"spitter": {"name": "Muscarine Spitter", "species": "u_spitter", "cost": [42, 0], "hp": 62, "dmg": 9, "range": 7.0, "cd": 1.05, "speed": 5.6, "train": 5.5, "poison": 2.5, "shot": "spit",
		"desc": "Ranged. Spits toxic slime."},
	"angel": {"name": "Destroying Angel", "species": "u_angel", "cost": [65, 40], "hp": 170, "dmg": 30, "range": 1.5, "cd": 0.85, "speed": 8.2, "train": 8.0, "poison": 6.0, "shot": "", "elite": true,
		"desc": "Pure-white assassin. Hunts cords and lone units."},
	"bruiser": {"name": "Morel Bruiser", "species": "u_bruiser", "cost": [40, 0], "hp": 140, "dmg": 12, "range": 1.3, "cd": 1.0, "speed": 5.0, "train": 5.5, "regen": 1.4, "shot": "",
		"desc": "Honeycombed tank. Regenerates."},
	"slinger": {"name": "Elf-Cup Slinger", "species": "u_slinger", "cost": [42, 0], "hp": 75, "dmg": 10, "range": 7.5, "cd": 1.15, "speed": 5.4, "train": 5.5, "regen": 0.8, "shot": "puff",
		"desc": "Scarlet cup that fires its asci like a cannon."},
	"stalker": {"name": "Cordyceps Stalker", "species": "u_stalker", "cost": [65, 40], "hp": 130, "dmg": 18, "range": 8.5, "cd": 1.35, "speed": 6.0, "train": 8.0, "regen": 1.0, "shot": "spit", "elite": true, "infects": true,
		"desc": "Parasite. Units it kills rise as your sporelings."},
	"lure_fly": {"name": "Fly-Lure", "species": "u_lure", "cost": [26, 0], "hp": 82, "dmg": 9, "range": 1.3, "cd": 0.55, "speed": 7.6, "train": 3.8, "shot": "",
		"desc": "Fast stinking skirmisher. Great at cutting cords."},
	"bomber": {"name": "Puffball Bomber", "species": "u_bomber", "cost": [46, 0], "hp": 66, "dmg": 14, "range": 8.0, "cd": 1.6, "speed": 5.4, "train": 6.0, "splash": 2.0, "shot": "puff", "arc": true,
		"desc": "Lobs bursting puffballs. Splash damage."},
	"sniper": {"name": "Pilobolus Sniper", "species": "u_sniper", "cost": [62, 40], "hp": 70, "dmg": 34, "range": 14.0, "cd": 2.3, "speed": 5.2, "train": 8.0, "shot": "egg", "elite": true,
		"desc": "Fires its sporangium at 25 m/s. Extreme range."},
	"zombie": {"name": "Cordyceps Thrall", "species": "u_zombie", "cost": [0, 0], "hp": 80, "dmg": 9, "range": 1.3, "cd": 0.9, "speed": 5.4, "train": 0.0, "shot": "",
		"desc": "A converted enemy, sprouting orange clubs."},
}

const TECHS := {
	"exoenzymes": {"name": "Exoenzymes", "tier": 1, "cost": [100, 0], "time": 22.0, "req": [],
		"desc": "+35% nutrient digestion. Unlocks Ganoderma Bracket."},
	"spore_sacs": {"name": "Spore Sacs", "tier": 1, "cost": [70, 30], "time": 20.0, "req": [],
		"desc": "+40% spore regen, spore cap 150. Unlocks Mycena Lantern."},
	"bootlaces": {"name": "Rhizomorph Bootlaces", "tier": 2, "cost": [90, 50], "time": 25.0, "req": ["exoenzymes"],
		"desc": "Cords reach +6 farther, have double health and regrow twice as fast. Units move 15% faster on your mycelium."},
	"phalloides": {"name": "Phalloides Lineage", "tier": 2, "cost": [130, 70], "time": 30.0, "req": ["spore_sacs"],
		"desc": "Unlocks the Death Cap Grove, Destroying Angels and the Fairy Ring spore action."},
	"universal_veil": {"name": "Universal Veil", "tier": 3, "cost": [160, 140], "time": 40.0, "req": ["phalloides", "bootlaces"],
		"desc": "All units +25% health. Unlocks Death Cap Bloom."},
	"hypocreales": {"name": "Hypocreales Graft", "tier": 2, "cost": [130, 70], "time": 30.0, "req": ["spore_sacs"],
		"desc": "Unlocks the Cordyceps Spire, Cordyceps Stalkers and the Zombify spore action."},
	"pyrophilous": {"name": "Pyrophilous Bloom", "tier": 3, "cost": [160, 140], "time": 40.0, "req": ["hypocreales", "bootlaces"],
		"desc": "Structures regenerate. Unlocks Wildfire: burn an area clean, then morels erupt from the ash."},
	"pilobolus": {"name": "Pilobolus Lineage", "tier": 2, "cost": [130, 70], "time": 30.0, "req": ["spore_sacs"],
		"desc": "Unlocks the Pilobolus Bed, Pilobolus Snipers and Spore Barrage."},
	"calvatia": {"name": "Calvatia Gigantea", "tier": 3, "cost": [160, 140], "time": 40.0, "req": ["pilobolus", "bootlaces"],
		"desc": "All units +20% speed. Unlocks Giant Puffball."},
}

# Spore actions. tech: required tech (empty = available from the start).
const ABILITIES := {
	"haze": {"name": "Muscimol Haze", "cost": 30, "cd": 10.0, "radius": 5.0, "tech": "",
		"desc": "Toxic fog: 8 dmg/s for 4 s and 40% slow to enemies inside."},
	"fairy_ring": {"name": "Fairy Ring", "cost": 50, "cd": 24.0, "radius": 7.0, "tech": "phalloides",
		"desc": "A ring erupts: 45 dmg to enemies on it and your mycelium floods the circle for 20 s."},
	"bloom": {"name": "Death Cap Bloom", "cost": 90, "cd": 55.0, "radius": 6.0, "tech": "universal_veil",
		"desc": "After 1.5 s: 260 dmg to structures and cords, 90 to units."},
	"volley": {"name": "Ascus Volley", "cost": 30, "cd": 9.0, "radius": 4.0, "tech": "",
		"desc": "Every ascus fires at once: 48 dmg in the area."},
	"zombify": {"name": "Zombify", "cost": 60, "cd": 28.0, "radius": 4.5, "tech": "hypocreales",
		"desc": "Up to 4 enemy non-elite units become your Cordyceps Thralls."},
	"wildfire": {"name": "Wildfire", "cost": 90, "cd": 55.0, "radius": 8.0, "tech": "pyrophilous",
		"desc": "Burns ALL mycelium in the area, 70 dmg to enemy units, 140 to structures. Morel mycelium then floods the ash for 25 s."},
	"lure": {"name": "Stench Lure", "cost": 25, "cd": 10.0, "radius": 6.0, "tech": "",
		"desc": "Carrion stink drags enemy units to the centre and slows them 50% for 4 s."},
	"barrage": {"name": "Spore Barrage", "cost": 55, "cd": 22.0, "radius": 6.0, "tech": "pilobolus",
		"desc": "14 sporangia rain over 3 s, 26 dmg each in a 2 m splash."},
	"giant_puffball": {"name": "Giant Puffball", "cost": 90, "cd": 55.0, "radius": 7.5, "tech": "calvatia",
		"desc": "Grow a colossal puffball. After 6 s it bursts: 320 dmg in a huge radius (half if killed first)."},
}


static func faction_color(f: int) -> Color:
	if f < 0:
		return Color(0.9, 0.85, 0.2)
	return FACTIONS[f]["color"]


static func world_to_uv(p: Vector2) -> Vector2:
	return Vector2((p.x + HALF_W) / (HALF_W * 2.0), (p.y + HALF_D) / (HALF_D * 2.0))
