extends RefCounted
# Every tunable number in RHIZOMORPH lives here: board layout, the forest's
# deposits and insect nests, factions, structures, units, tech trees and spore
# actions. DESIGN.md explains why the three courts eat the way they do.

const HALF_W := 96.0          # a 192 x 144 m stretch of forest floor
const HALF_D := 72.0
const SIM_RES := 3            # GPU mycelium cells per world unit (= board.gd VRES)
const SIM_W := 576
const SIM_H := 432
const COARSE_W := 192         # 1 cell per world unit, read back to the CPU
const COARSE_H := 144

const NEUTRAL := 3            # faction index of the forest's insects
const POP_CAP := 40
const BASE_LINK := 14.0       # how far a rhizomorph cord can reach
const CORD_REGROW := 12.0     # seconds before a severed cord regrows
const NUTRIENT_RATE := 0.013  # income per (density * nutrient) per coarse cell per second
const SUGAR_SCALE := 0.5      # a tree's "sugar" * this * vigor term = sugar/s split between its mantles
const SPORE_CAP := 100.0
const CORD_HP := 90.0
const CORD_CAP := 4.0         # income a cord can carry per second (x2 with Bootlaces)
const HOP_LOSS := 0.03        # income lost at every cord hop on the way to the Heart
const STARVE_DPS := 0.012     # fraction of max hp lost per second by a cut-off structure
const AGGRO := 9.0            # how far idle units notice enemies
const CAST_RANGE := 16.0      # spore actions land within this of your units / structures

# --- the Court's trees ---
const MANTLE_FEED := 0.4      # minerals/s each mantle pays its tree
const VIGOR_REST := 0.55      # where an unpartnered tree's vigor settles
const VIGOR_PER_MANTLE := 0.15
const VIGOR_RATE := 0.01      # vigor/s toward its target
const WEB_BONUS := 0.1        # +sugar per extra tree linked through the network (max 4)
const MOTHER_BONUS := 0.25
const FRUIT_SPORES := 0.12    # spores/s per mantle on a tree with vigor >= 0.7
const GROVE_REGEN := 2.5      # hp/s for Court units inside the roots of a tree the Court feeds
const CARBON_GIVE := 0.35     # vigor Carbon Transfer pours into one tree, drawn from the others
const MAST_TIME := 20.0       # seconds a Mast Year lasts
const MAST_MULT := 3.0        # sugar and fruiting spores during it
const MAST_COST := 0.15       # vigor every fed tree loses when it ends
const NURSERY_TREE := {"name": "Young Birch", "radius": 1.2, "roots": 8.0, "sugar": 2.6, "kind": "birch", "partner": 1.3, "borer": 1.0}

# --- the Hollow's deposits ---
const BRACKET_RATE := 1.65    # cellulose/s a Rot Bracket digests from its deposit
const CORPSE_RATE := 1.5      # nitrogen/s drawn from a corpse under Hollow mycelium
const CORPSE_LIFE := 60.0
const SOIL_SHARE := 0.35      # the Hollow digests bare soil at this fraction of the Court's rate
const HONEY_ROT := 0.02       # vigor/s a Honey Rot drains from its tree

# --- the Choir's hosts ---
const THRALL_DECAY := 0.0055  # fraction of max hp lost per second
const INFECT_RANGE := 8.0     # kills this close to a Choir body rise as thralls
const HOST_RANGE := 6.0       # a Choir structure grows from a thrall this close to the spot
const INSECT_CAP := 70

const START_POS := [Vector2(-70, 44), Vector2(70, 44), Vector2(0, -52)]

# partner: how much sugar each tree species gives the Amanita Court.
# borer: how hard Agrilus jewel beetles hit it (each broadleaf has its own Agrilus
# specialist - chestnut borer on oak, bronze birch borer, emerald ash borer; conifers resist).
# old: an old-growth giant, a Mother Tree candidate.
const TREES := [
	# the old-growth stand in the middle
	{"name": "Old Oak", "pos": Vector2(0, 6), "radius": 3.2, "roots": 16.0, "sugar": 7.0, "kind": "oak", "partner": 1.0, "borer": 1.0, "old": true},
	{"name": "Great Hemlock", "pos": Vector2(-18, 22), "radius": 2.6, "roots": 13.0, "sugar": 5.0, "kind": "hemlock", "partner": 0.8, "borer": 0.4, "old": true},
	{"name": "Elder Oak", "pos": Vector2(18, 24), "radius": 2.8, "roots": 14.0, "sugar": 6.0, "kind": "oak", "partner": 1.0, "borer": 1.0, "old": true},
	# the Court's birch stand (northwest)
	{"name": "Birch", "pos": Vector2(-50, 30), "radius": 1.5, "roots": 9.0, "sugar": 3.0, "kind": "birch", "partner": 1.3, "borer": 1.0},
	{"name": "Birch", "pos": Vector2(-62, 16), "radius": 1.5, "roots": 9.0, "sugar": 3.0, "kind": "birch", "partner": 1.3, "borer": 1.0},
	{"name": "Hemlock", "pos": Vector2(-78, 60), "radius": 2.0, "roots": 11.0, "sugar": 3.5, "kind": "hemlock", "partner": 0.8, "borer": 0.4},
	# by the Hollow's windfall (northeast)
	{"name": "Oak", "pos": Vector2(50, 32), "radius": 2.2, "roots": 12.0, "sugar": 4.5, "kind": "oak", "partner": 1.0, "borer": 1.0},
	{"name": "Birch", "pos": Vector2(78, 20), "radius": 1.5, "roots": 9.0, "sugar": 3.0, "kind": "birch", "partner": 1.3, "borer": 1.0},
	{"name": "Hemlock", "pos": Vector2(62, 64), "radius": 2.0, "roots": 11.0, "sugar": 3.5, "kind": "hemlock", "partner": 0.8, "borer": 0.4},
	# near the Choir's anthills (south)
	{"name": "Hemlock", "pos": Vector2(-4, -30), "radius": 2.0, "roots": 11.0, "sugar": 3.5, "kind": "hemlock", "partner": 0.8, "borer": 0.4},
	{"name": "Oak", "pos": Vector2(24, -42), "radius": 2.2, "roots": 12.0, "sugar": 4.5, "kind": "oak", "partner": 1.0, "borer": 1.0},
	{"name": "Birch", "pos": Vector2(-32, -50), "radius": 1.5, "roots": 9.0, "sugar": 3.0, "kind": "birch", "partner": 1.3, "borer": 1.0},
	# scattered between
	{"name": "Birch", "pos": Vector2(-36, -2), "radius": 1.5, "roots": 9.0, "sugar": 3.0, "kind": "birch", "partner": 1.3, "borer": 1.0},
	{"name": "Birch", "pos": Vector2(34, -4), "radius": 1.5, "roots": 9.0, "sugar": 3.0, "kind": "birch", "partner": 1.3, "borer": 1.0},
	{"name": "Oak", "pos": Vector2(-40, 58), "radius": 2.0, "roots": 11.0, "sugar": 4.0, "kind": "oak", "partner": 1.0, "borer": 1.0},
	{"name": "Hemlock", "pos": Vector2(66, -28), "radius": 2.0, "roots": 11.0, "sugar": 3.5, "kind": "hemlock", "partner": 0.8, "borer": 0.4},
]
const MANTLES_PER_TREE := 3
const TREE_LINK := 30.0       # trees closer than this share roots (vision, the Web)

# pos, radius, height
const ROCKS := [
	[Vector2(20, 62), 7.0, 3.4], [Vector2(84, -56), 6.0, 3.0], [Vector2(-84, -60), 5.0, 2.6], [Vector2(-88, 30), 4.0, 2.0],
	[Vector2(40, -18), 3.0, 1.4], [Vector2(-8, 38), 2.4, 1.1], [Vector2(88, 4), 3.4, 1.8], [Vector2(-60, 64), 3.6, 1.8],
	[Vector2(6, -66), 2.6, 1.2], [Vector2(-28, 8), 2.2, 1.0],
	# stepping stones across the stream
	[Vector2(-18.5, -39), 1.3, 0.75], [Vector2(-16, -42.5), 1.2, 0.7], [Vector2(-14, -46), 1.2, 0.7],
]
const PUDDLES := [
	[Vector2(-22, 36), 4.4], [Vector2(26, 38), 3.6], [Vector2(10, -20), 3.2], [Vector2(64, -6), 3.6], [Vector2(-74, 6), 3.0],
	[Vector2(40, 6), 3.0], [Vector2(-52, -34), 3.0], [Vector2(50, -60), 3.4],
]
# a stream down the west side: polyline, half-width. Crossed by a log bridge and stepping stones.
const STREAM := [Vector2(-99, -12), Vector2(-72, -20), Vector2(-46, -16), Vector2(-26, -26), Vector2(-16, -42), Vector2(-22, -76)]
const STREAM_W := 2.2
# a, b, radius, cellulose stock. Rotting logs breed stag beetles.
const LOGS := [
	[Vector2(56, 22), Vector2(76, 30), 1.6, 1200.0], [Vector2(54, 12), Vector2(70, 4), 1.3, 900.0],
	[Vector2(42, 28), Vector2(38, 44), 1.2, 700.0], [Vector2(-80, -42), Vector2(-60, -48), 1.5, 1000.0],
	[Vector2(24, -60), Vector2(46, -56), 1.6, 1100.0], [Vector2(-50, -8), Vector2(-42, -24), 1.1, 600.0],
	[Vector2(-30, 62), Vector2(-10, 66), 1.3, 800.0], [Vector2(6, -10), Vector2(16, -15), 1.0, 500.0],
]
# pos, cellulose, nitrogen. Litter breeds springtails.
const LITTER := [
	[Vector2(-58, 34), 220.0, 20.0], [Vector2(62, -8), 220.0, 20.0], [Vector2(12, -44), 220.0, 20.0],
	[Vector2(8, -4), 260.0, 25.0], [Vector2(-12, 28), 240.0, 22.0], [Vector2(24, 30), 240.0, 22.0],
	[Vector2(-42, -58), 200.0, 20.0], [Vector2(40, -44), 200.0, 20.0], [Vector2(-74, -24), 200.0, 20.0],
	[Vector2(78, -46), 200.0, 20.0], [Vector2(0, 58), 220.0, 20.0],
]
const ANTHILLS := [Vector2(-56, 52), Vector2(54, 56), Vector2(-6, -64), Vector2(30, -26), Vector2(-80, -4), Vector2(82, -20)]
# per nest: insect, cap, seconds between births
const NESTS := {
	"anthill": ["ant", 5, 36.0],
	"log": ["stag", 1, 75.0],
	"snag": ["beetle", 3, 30.0],
	"weak_tree": ["beetle", 2, 40.0],   # a tree below 0.4 vigor draws bark beetles
	"litter": ["springtail", 3, 34.0],
	"corpse": ["fly", 1, 12.0],
}

const FACTIONS := [
	{
		"key": "amanita", "name": "Amanita Court", "color": Color(0.92, 0.18, 0.12),
		"motto": "Feed the grove and the grove feeds you.",
		"economy": "mycorrhizal",
		"res_names": ["Minerals", "Sugar", "Spores"],
		"start_res": [260.0, 100.0, 30.0],
		"starters": ["wartling", "wartling", "wartling"],
		"heart": "heart_amanita",
		"build": ["node", "mantle", "agaric_ring", "cortina_thicket", "root_snare", "truffle", "nursery", "deathcap_grove"],
		"abilities": ["haze", "carbon_transfer", "fairy_ring", "bloom", "mast_year"],
		"techs": ["hartig_net", "muscarine", "root_signalling", "phalloides", "bootlaces", "universal_veil", "old_growth", "mast_year"],
		"ai_techs": ["hartig_net", "muscarine", "root_signalling", "phalloides", "mast_year", "bootlaces", "universal_veil", "old_growth"],
		"decor": ["agaric_button", "mycena_white"],
	},
	{
		"key": "morel", "name": "Morel Hollow", "color": Color(0.98, 0.8, 0.22),
		"motto": "Every fight is a feast.",
		"economy": "saprotroph",
		"res_names": ["Cellulose", "Nitrogen", "Spores"],
		"start_res": [280.0, 60.0, 30.0],
		"starters": ["bruiser", "bruiser", "slinger"],
		"heart": "heart_morel",
		"build": ["node", "rot_bracket", "inkcap_bed", "morel_patch", "earthstar", "birds_nest", "honey_rot", "pilobolus_bed"],
		"abilities": ["volley", "wildfire", "giant_puffball"],
		"techs": ["exoenzymes", "necrophagy", "armillaria", "pilobolus", "pyrophilous", "calvatia", "humus_engine"],
		"ai_techs": ["exoenzymes", "necrophagy", "armillaria", "pilobolus", "pyrophilous", "calvatia", "humus_engine"],
		"decor": ["morel_small", "elf_cup_small"],
	},
	{
		"key": "veiled", "name": "Veiled Choir", "color": Color(0.74, 0.46, 1.0),
		"motto": "The forest walks for us.",
		"economy": "parasite",
		"res_names": ["Biomass", "Hosts", "Spores"],
		"start_res": [160.0, 0.0, 60.0],
		"starters": ["t_ant", "t_ant", "t_ant", "t_ant", "t_beetle"],
		"heart": "heart_veiled",
		"build": ["stinkhorn_lure", "clathrus_cage", "cordyceps_spire", "brood_chamber"],
		"abilities": ["lure", "zombify", "pandemic", "borer_swarm"],
		"techs": ["stench_glands", "chitin_lysis", "hypocreales", "summit", "ophiocordyceps", "pandemic", "brood", "agrilus"],
		"ai_techs": ["chitin_lysis", "stench_glands", "hypocreales", "ophiocordyceps", "agrilus", "summit", "pandemic", "brood"],
		"decor": ["puffball_small", "inkcap"],
	},
]

const BUILD_KEYS := ["N", "M", "B", "T", "G", "L", "K", "H"]
const ABILITY_KEYS := ["Z", "X", "C", "V", "R"]

# radius: footprint / click radius. myc: radius of mycelium this structure feeds.
# cost: [res0, res1] in the building court's own resources.
# on: "tree" (root zone), "deposit" (log / snag / branch), "trunk".
const STRUCTURES := {
	"heart_amanita": {"name": "Sclerotium of the Court", "species": "giant_agaric", "hp": 2400, "radius": 3.6, "myc": 15.0, "spores": 0.5, "income": 2.0, "trains": [], "research": true,
		"attack": {"dmg": 11, "range": 9.0, "cd": 0.8, "poison": 2.5, "shot": "spit"},
		"desc": "Your Heart. Researches lineages and spits muscarine at intruders. If it falls, the Court rots."},
	"heart_morel": {"name": "Sclerotium of the Hollow", "species": "giant_morel", "hp": 2700, "radius": 3.6, "myc": 15.0, "spores": 0.5, "income": 2.0, "trains": [], "research": true,
		"attack": {"dmg": 13, "range": 8.0, "cd": 1.1, "splash": 2.0, "shot": "puff"},
		"desc": "Your Heart. Researches lineages and bellows spores at intruders. If it falls, the Hollow rots."},
	"heart_veiled": {"name": "Sclerotium of the Choir", "species": "giant_veiled", "hp": 2300, "radius": 3.6, "myc": 11.0, "spores": 1.0, "income": 1.8, "trains": [], "research": true, "lure": 12.0,
		"attack": {"dmg": 9, "range": 9.0, "cd": 0.8, "shot": "spit"},
		"desc": "Your Heart. Researches lineages, spits at intruders and slowly infects insects that wander close. If it falls, the Choir rots."},
	"node": {"name": "Armillaria Node", "species": "armillaria", "cost": [55, 0], "hp": 320, "build": 7.0, "radius": 1.6, "myc": 9.5,
		"desc": "Rhizomorph hub. Cheap. Pushes your mycelium outward and relays supply."},

	# --- Amanita Court ---
	"mantle": {"name": "Hartig Mantle", "species": "chanterelle", "cost": [70, 0], "hp": 360, "build": 9.0, "radius": 1.6, "myc": 6.0, "on": "tree",
		"desc": "Sheathes a tree's roots. Pays it 0.6 minerals/s and the tree pays back SUGAR - more the healthier it grows. Linked trees pool their sugar."},
	"agaric_ring": {"name": "Fly Agaric Ring", "species": "fly_agaric", "cost": [100, 15], "hp": 650, "build": 11.0, "radius": 2.4, "myc": 7.0, "trains": ["wartling", "spitter"],
		"desc": "Fruiting body. Trains Wartlings and Muscarine Spitters."},
	"root_snare": {"name": "Root Snare", "species": "clathrus", "cost": [60, 30], "hp": 520, "build": 10.0, "radius": 1.8, "myc": 5.0, "on": "tree",
		"attack": {"dmg": 9, "range": 9.5, "cd": 0.9, "slow": 0.5, "slow_t": 2.0, "shot": "spit", "vigor": true},
		"desc": "The tree's own roots, turned. Grips and slows. Hits harder the healthier its tree."},
	"cortina_thicket": {"name": "Cortina Thicket", "species": "cortina_thicket", "cost": [100, 30], "hp": 600, "build": 11.0, "radius": 2.2, "myc": 6.0, "on": "tree", "fed_tree": true, "trains": ["milkcap", "webcap"],
		"desc": "Webcaps and milkcaps fruiting with their partner tree - it must stand in the roots of a tree you feed. Trains Milkcaps and Violet Webcaps."},
	"truffle": {"name": "Truffle Mine", "species": "truffle", "cost": [35, 15], "hp": 90, "build": 6.0, "radius": 0.9, "myc": 0.0, "on": "territory", "unlinked": true, "hidden": true,
		"mine": {"trigger": 2.5, "radius": 4.0, "dmg": 70, "slow": 0.5, "slow_t": 3.0},
		"desc": "A buried truffle: no cord, no glow, invisible to enemies until they are almost on it. Bursts in a pungent spore cloud when they walk over it (70 dmg, slows). Plant it in your own territory."},
	"nursery": {"name": "Mother Tree Nursery", "species": "nursery", "cost": [120, 60], "hp": 350, "build": 120.0, "radius": 1.8, "myc": 6.0, "on": "gap", "grows_tree": true,
		"desc": "A sapling, fed by the network in a sunlit gap. When it finishes growing (2 min) it becomes a new birch you can mantle. Only the Court grows the forest."},
	"deathcap_grove": {"name": "Death Cap Grove", "species": "death_cap", "cost": [110, 80], "hp": 700, "build": 14.0, "radius": 2.4, "myc": 7.0, "trains": ["angel"], "req": "phalloides",
		"desc": "Amanita phalloides colony. Trains Destroying Angels."},

	# --- Morel Hollow ---
	"rot_bracket": {"name": "Rot Bracket", "species": "bracket", "cost": [80, 0], "hp": 500, "build": 10.0, "radius": 1.8, "myc": 6.0, "on": "deposit",
		"desc": "Ganoderma shelf on a log, snag or fallen branch. Digests it for 1.65 cellulose/s until nothing is left."},
	"inkcap_bed": {"name": "Inkcap Bed", "species": "inkcap_bed", "cost": [90, 0], "hp": 420, "build": 9.0, "radius": 1.8, "myc": 7.0, "gather": 10.0,
		"desc": "Shaggy inkcaps deliquesce over the dead. Pulls corpses within 10 m in and keeps them from rotting away, and digests leaf litter nearby."},
	"morel_patch": {"name": "Morel Patch", "species": "morel", "cost": [120, 0], "hp": 760, "build": 11.0, "radius": 2.4, "myc": 7.0, "spores": 0.1, "trains": ["bruiser", "slinger", "bomber"],
		"desc": "Fruiting body. Trains Morel Bruisers, Elf-Cup Slingers and Puffball Bombers."},
	"earthstar": {"name": "Earthstar", "species": "earthstar", "cost": [100, 0], "hp": 600, "build": 10.0, "radius": 1.8, "myc": 5.0, "spores": 0.2,
		"attack": {"dmg": 15, "range": 7.5, "cd": 1.3, "splash": 2.6, "shot": "puff"},
		"desc": "Geastrum tower. Bellows clouds of spores that hit everything nearby. +0.2 spores/s."},
	"birds_nest": {"name": "Bird's Nest", "species": "birds_nest", "cost": [110, 15], "hp": 480, "build": 10.0, "radius": 1.8, "myc": 5.0,
		"attack": {"dmg": 22, "range": 13.0, "cd": 2.4, "splash": 2.2, "shot": "egg", "arc": true},
		"desc": "Cyathus splash-cup artillery. Long range, lobs peridioles."},
	"honey_rot": {"name": "Honey Rot", "species": "armillaria", "cost": [60, 20], "hp": 380, "build": 9.0, "radius": 1.6, "myc": 5.0, "on": "tree", "req": "armillaria",
		"desc": "Armillaria in a living tree's roots. Drains its vigor until it dies as a snag - a feast for brackets, and a tree the Court can no longer use."},
	"pilobolus_bed": {"name": "Pilobolus Bed", "species": "pilobolus", "cost": [130, 40], "hp": 560, "build": 14.0, "radius": 2.2, "myc": 7.0, "trains": ["sniper"], "req": "pilobolus",
		"desc": "Dung-fungus hat-throwers. Trains Pilobolus Snipers."},

	# --- Veiled Choir: no cords; each grows out of a sacrificed thrall ---
	"stinkhorn_lure": {"name": "Stinkhorn Lure", "species": "veiled_lady", "cost": [60, 0], "hp": 480, "build": 8.0, "radius": 2.0, "myc": 6.0, "spores": 0.4, "income": 0.4, "lure": 18.0,
		"desc": "Veiled Lady stinkhorn. Its carrion stench pulls insects within 18 m in and infects them. Breeds flies. +0.4 biomass/s, +0.4 spores/s."},
	"clathrus_cage": {"name": "Clathrus Cage", "species": "clathrus", "cost": [80, 0], "hp": 520, "build": 10.0, "radius": 1.8, "myc": 5.0,
		"attack": {"dmg": 11, "range": 9.5, "cd": 0.9, "slow": 0.45, "slow_t": 2.0, "shot": "spit"},
		"desc": "Red latticed stinkhorn tower. Its slime slows what it hits."},
	"cordyceps_spire": {"name": "Cordyceps Spire", "species": "cordyceps", "cost": [90, 0], "hp": 700, "build": 12.0, "radius": 2.2, "myc": 7.0, "trains": ["stalker"], "req": "hypocreales",
		"desc": "Parasitic Hypocreales. Grows Cordyceps Stalkers from spores."},
	"brood_chamber": {"name": "Brood Chamber", "species": "giant_puffball", "cost": [140, 0], "hp": 900, "build": 14.0, "radius": 2.6, "myc": 8.0, "req": "brood", "brood": 9.0,
		"desc": "Thralls within 9 m stop decaying and heal 3 hp/s."},
}

# thrall: decays over time (Choir). insect: neutral wildlife. host: the thrall an insect becomes.
const UNITS := {
	"wartling": {"name": "Wartling", "species": "u_wartling", "cost": [14, 16], "hp": 100, "dmg": 10, "range": 1.3, "cd": 0.75, "speed": 6.2, "train": 4.5, "poison": 3.0, "shot": "",
		"desc": "Warty melee sporeling. Poisons on hit."},
	"spitter": {"name": "Muscarine Spitter", "species": "u_spitter", "cost": [16, 20], "hp": 62, "dmg": 9, "range": 7.0, "cd": 1.05, "speed": 5.6, "train": 5.5, "poison": 2.5, "shot": "spit",
		"desc": "Ranged. Spits toxic slime."},
	"angel": {"name": "Destroying Angel", "species": "u_angel", "cost": [30, 70], "hp": 170, "dmg": 30, "range": 1.5, "cd": 0.85, "speed": 8.2, "train": 8.0, "poison": 6.0, "shot": "", "elite": true, "cutter": true,
		"desc": "Pure-white assassin. Hunts cords and lone units."},

	"milkcap": {"name": "Saffron Milkcap", "species": "u_milkcap", "cost": [20, 18], "hp": 170, "dmg": 9, "range": 1.3, "cd": 1.0, "speed": 5.0, "train": 6.0, "shot": "",
		"latex": {"dmg": 3.0, "slow": 0.4, "slow_t": 2.0},
		"desc": "Lactarius. Bleeds sticky orange latex when struck: melee attackers are slowed and stung."},
	"webcap": {"name": "Violet Webcap", "species": "u_webcap", "cost": [18, 22], "hp": 70, "dmg": 7, "range": 8.0, "cd": 1.4, "speed": 5.4, "train": 6.0, "shot": "web", "root": 1.2,
		"desc": "Cortinarius violaceus. Spits cobweb veil that roots its target in place for a moment."},
	"bruiser": {"name": "Morel Bruiser", "species": "u_bruiser", "cost": [32, 7], "hp": 140, "dmg": 12, "range": 1.3, "cd": 1.0, "speed": 5.0, "train": 5.5, "regen": 1.4, "shot": "",
		"desc": "Honeycombed tank. Regenerates."},
	"slinger": {"name": "Elf-Cup Slinger", "species": "u_slinger", "cost": [32, 8], "hp": 75, "dmg": 10, "range": 7.5, "cd": 1.15, "speed": 5.4, "train": 5.5, "regen": 0.8, "shot": "puff",
		"desc": "Scarlet cup that fires its asci like a cannon."},
	"bomber": {"name": "Puffball Bomber", "species": "u_bomber", "cost": [34, 11], "hp": 66, "dmg": 14, "range": 8.0, "cd": 1.6, "speed": 5.4, "train": 6.0, "splash": 2.0, "shot": "puff", "arc": true,
		"desc": "Lobs bursting puffballs. Splash damage."},
	"sniper": {"name": "Pilobolus Sniper", "species": "u_sniper", "cost": [45, 55], "hp": 70, "dmg": 34, "range": 14.0, "cd": 2.3, "speed": 5.2, "train": 8.0, "shot": "egg", "elite": true,
		"desc": "Fires its sporangium at 25 m/s. Extreme range. Costs nitrogen - feed on the dead."},

	"t_ant": {"name": "Ant Thrall", "species": "t_ant", "cost": [0, 0], "hp": 55, "dmg": 8, "range": 1.2, "cd": 0.6, "speed": 7.4, "train": 0.0, "shot": "", "thrall": true, "cutter": true,
		"desc": "An infected ant. Fast, cheap, a good cord cutter. Decays."},
	"t_beetle": {"name": "Beetle Thrall", "species": "t_beetle", "cost": [0, 0], "hp": 180, "dmg": 13, "range": 1.3, "cd": 1.1, "speed": 4.6, "train": 0.0, "shot": "", "thrall": true, "armor": 0.3, "bores": true,
		"desc": "An infected bark beetle. Armoured against spit and spores; bores into trees. Decays."},
	"t_stag": {"name": "Stag Thrall", "species": "t_stag", "cost": [0, 0], "hp": 220, "dmg": 15, "range": 1.6, "cd": 1.3, "speed": 4.2, "train": 0.0, "shot": "", "thrall": true, "armor": 0.4,
		"desc": "An infected stag beetle. The Choir's heaviest body: armoured, slow, crushing. Decays."},
	"t_fly": {"name": "Fly Thrall", "species": "t_fly", "cost": [0, 0], "hp": 45, "dmg": 6, "range": 1.2, "cd": 0.6, "speed": 9.0, "train": 0.0, "shot": "", "thrall": true, "flies": true, "sight": 18.0,
		"desc": "An infected fly. Crosses water; sees far. Fragile. Decays."},
	"zombie": {"name": "Cordyceps Thrall", "species": "u_zombie", "cost": [0, 0], "hp": 80, "dmg": 9, "range": 1.3, "cd": 0.9, "speed": 5.4, "train": 0.0, "shot": "", "thrall": true,
		"desc": "A converted enemy, sprouting orange clubs. Decays."},
	"stalker": {"name": "Cordyceps Stalker", "species": "u_stalker", "cost": [0, 0], "spores": 85, "hp": 120, "dmg": 16, "range": 8.5, "cd": 1.35, "speed": 6.0, "train": 8.0, "regen": 1.0, "shot": "spit", "elite": true, "infects": true,
		"desc": "Parasite grown from spores. Everything it kills rises as your thrall."},

	"ant": {"name": "Wood Ant", "species": "i_ant", "cost": [0, 0], "hp": 25, "dmg": 4, "range": 1.0, "cd": 0.8, "speed": 6.0, "train": 0.0, "shot": "", "insect": true, "host": "t_ant",
		"desc": "Forages in columns. Carries off the dead."},
	"beetle": {"name": "Bark Beetle", "species": "i_beetle", "cost": [0, 0], "hp": 60, "dmg": 7, "range": 1.1, "cd": 1.2, "speed": 3.0, "train": 0.0, "shot": "", "insect": true, "host": "t_beetle", "armor": 0.3, "bores": true,
		"desc": "Bores into living trees and weakens them."},
	"fly": {"name": "Carrion Fly", "species": "i_fly", "cost": [0, 0], "hp": 15, "dmg": 2, "range": 1.0, "cd": 1.0, "speed": 7.5, "train": 0.0, "shot": "", "insect": true, "host": "t_fly", "flies": true,
		"desc": "Drawn to the dead and to stinkhorns."},
	"stag": {"name": "Stag Beetle", "species": "i_stag", "cost": [0, 0], "hp": 110, "dmg": 10, "range": 1.4, "cd": 1.3, "speed": 2.8, "train": 0.0, "shot": "", "insect": true, "host": "t_stag", "armor": 0.4,
		"desc": "Its larvae spend years in rotting logs. Slow, armoured, and not to be grabbed."},
	"borer": {"name": "Agrilus Borer", "species": "i_borer", "cost": [0, 0], "hp": 14, "dmg": 2, "range": 1.0, "cd": 1.0, "speed": 5.0, "train": 0.0, "shot": "", "insect": true, "host": "", "flies": true, "bores": true, "bore": 0.007, "life": 45.0,
		"desc": "A jewel beetle. Its larvae girdle a tree's living wood. Lives 45 s."},
	"springtail": {"name": "Springtail Swarm", "species": "i_springtail", "cost": [0, 0], "hp": 30, "dmg": 3, "range": 1.0, "cd": 1.0, "speed": 4.0, "train": 0.0, "shot": "", "insect": true, "host": "", "grazes": true,
		"desc": "Grazes mycelium, eating into whichever court's ground it sits on."},
}

# cost: [res0, res1] in the researching court's own resources; spores: extra spore cost.
const TECHS := {
	# Amanita Court
	"hartig_net": {"name": "Hartig Net", "tier": 1, "cost": [90, 20], "time": 22.0, "req": [],
		"desc": "Mantles give +35% sugar and raise their tree's vigor twice as fast."},
	"muscarine": {"name": "Muscarine", "tier": 1, "cost": [80, 30], "time": 20.0, "req": [],
		"desc": "All poison +50%."},
	"root_signalling": {"name": "Root Signalling", "tier": 2, "cost": [90, 80], "time": 26.0, "req": ["hartig_net"],
		"desc": "Linked trees share vigor, and you are warned when one is attacked."},
	"phalloides": {"name": "Phalloides Lineage", "tier": 2, "cost": [90, 90], "time": 30.0, "req": ["muscarine"],
		"desc": "Unlocks the Death Cap Grove, Destroying Angels and the Fairy Ring spore action."},
	"bootlaces": {"name": "Rhizomorph Bootlaces", "tier": 2, "cost": [90, 70], "time": 25.0, "req": ["hartig_net"],
		"desc": "Cords reach +6 farther, have double health and regrow twice as fast. Units move 15% faster on your mycelium."},
	"universal_veil": {"name": "Universal Veil", "tier": 3, "cost": [130, 160], "time": 40.0, "req": ["phalloides"],
		"desc": "All units +25% health. Unlocks Death Cap Bloom."},
	"mast_year": {"name": "Mast Year", "tier": 3, "cost": [120, 140], "time": 36.0, "req": ["root_signalling"],
		"desc": "Unlocks Mast Year: every healthy tree you feed fruits at once."},
	"old_growth": {"name": "Old-Growth Pact", "tier": 3, "cost": [130, 160], "time": 40.0, "req": ["root_signalling"],
		"desc": "Every tree takes a 4th mantle, and a Mother Tree needs only 2 links."},
	# Morel Hollow
	"exoenzymes": {"name": "Exoenzymes", "tier": 1, "cost": [100, 0], "time": 22.0, "req": [],
		"desc": "+35% digestion of soil and deposits; mycelium spreads faster."},
	"necrophagy": {"name": "Necrophagy", "tier": 1, "cost": [80, 20], "time": 20.0, "req": [],
		"desc": "Corpses give +50% nitrogen and rot away half as fast."},
	"armillaria": {"name": "Armillaria Bootlaces", "tier": 2, "cost": [110, 60], "time": 26.0, "req": ["exoenzymes"],
		"desc": "Cords reach +6, double health, regrow twice as fast; units faster on your mycelium. Unlocks Honey Rot."},
	"pilobolus": {"name": "Pilobolus Lineage", "tier": 2, "cost": [110, 80], "time": 30.0, "req": ["necrophagy"],
		"desc": "Unlocks the Pilobolus Bed and Pilobolus Snipers."},
	"pyrophilous": {"name": "Pyrophilous Bloom", "tier": 2, "cost": [110, 70], "time": 30.0, "req": ["exoenzymes"],
		"desc": "Structures regenerate. Unlocks Wildfire: burn an area clean, then morels erupt from the ash."},
	"calvatia": {"name": "Calvatia Gigantea", "tier": 3, "cost": [140, 140], "time": 40.0, "req": ["pilobolus"],
		"desc": "Bombers splash 30% wider. Unlocks Giant Puffball."},
	"humus_engine": {"name": "Humus Engine", "tier": 3, "cost": [140, 140], "time": 40.0, "req": ["armillaria"],
		"desc": "Humus left by finished deposits feeds twice as much."},
	# Veiled Choir
	"stench_glands": {"name": "Stench Glands", "tier": 1, "cost": [40, 0], "spores": 60, "time": 20.0, "req": [],
		"desc": "Lures and the Heart pull insects from 50% farther."},
	"chitin_lysis": {"name": "Chitin Lysis", "tier": 1, "cost": [40, 0], "spores": 60, "time": 20.0, "req": [],
		"desc": "Thralls decay 40% slower and have +15% health."},
	"hypocreales": {"name": "Hypocreales Graft", "tier": 2, "cost": [60, 0], "spores": 100, "time": 28.0, "req": ["stench_glands"],
		"desc": "Unlocks the Cordyceps Spire, Cordyceps Stalkers and the Zombify spore action."},
	"summit": {"name": "Summit Disease", "tier": 2, "cost": [60, 0], "spores": 90, "time": 26.0, "req": ["chitin_lysis"],
		"desc": "Sporulating thralls burst for +50% spores and biomass, and 70 damage."},
	"ophiocordyceps": {"name": "Ophiocordyceps", "tier": 2, "cost": [60, 0], "spores": 90, "time": 26.0, "req": ["stench_glands"],
		"desc": "Beetle Thralls bore trees twice as fast, and insects near your thralls slowly fall sick."},
	"pandemic": {"name": "Pandemic", "tier": 3, "cost": [80, 0], "spores": 150, "time": 40.0, "req": ["hypocreales"],
		"desc": "Unlocks the Pandemic spore action."},
	"agrilus": {"name": "Agrilus Swarm", "tier": 3, "cost": [80, 0], "spores": 120, "time": 36.0, "req": ["ophiocordyceps"],
		"desc": "Unlocks Agrilus Swarm: call jewel-beetle borers down on a tree."},
	"brood": {"name": "Brood Chamber", "tier": 3, "cost": [100, 0], "spores": 120, "time": 36.0, "req": ["summit"],
		"desc": "Unlocks the Brood Chamber. Population cap 50."},
}

# Spore actions. tech: required tech (empty = available from the start).
const ABILITIES := {
	"haze": {"name": "Muscimol Haze", "cost": 30, "cd": 10.0, "radius": 5.0, "tech": "",
		"desc": "Toxic fog: 8 dmg/s for 4 s and 40% slow to enemies inside."},
	"carbon_transfer": {"name": "Carbon Transfer", "cost": 35, "cd": 30.0, "radius": 6.0, "tech": "",
		"desc": "Cast on a tree you feed: the network pours +0.35 vigor into it, drawn from your other fed trees. Saves a tree under Honey Rot or borers - and lets you bluff which tree is weak."},
	"mast_year": {"name": "Mast Year", "cost": 80, "cd": 120.0, "radius": 6.0, "tech": "mast_year",
		"desc": "Cast on any tree you feed: for 20 s every fed tree with vigor 0.5+ pays triple sugar and fruiting spores. Afterwards they are spent: -0.15 vigor each."},
	"fairy_ring": {"name": "Fairy Ring", "cost": 50, "cd": 24.0, "radius": 7.0, "tech": "phalloides",
		"desc": "A ring erupts: 45 dmg to enemies on it and your mycelium floods the circle for 20 s."},
	"bloom": {"name": "Death Cap Bloom", "cost": 90, "cd": 55.0, "radius": 6.0, "tech": "universal_veil",
		"desc": "After 1.5 s: 260 dmg to structures and cords, 90 to units."},
	"volley": {"name": "Ascus Volley", "cost": 30, "cd": 9.0, "radius": 4.0, "tech": "",
		"desc": "Every ascus fires at once: 48 dmg in the area."},
	"wildfire": {"name": "Wildfire", "cost": 90, "cd": 55.0, "radius": 8.0, "tech": "pyrophilous",
		"desc": "Burns ALL mycelium in the area, 70 dmg to enemy units, 140 to structures. Morel mycelium then floods the ash for 25 s."},
	"giant_puffball": {"name": "Giant Puffball", "cost": 90, "cd": 55.0, "radius": 7.5, "tech": "calvatia",
		"desc": "Grow a colossal puffball. After 6 s it bursts: 320 dmg in a huge radius (half if killed first)."},
	"lure": {"name": "Stench Lure", "cost": 25, "cd": 10.0, "radius": 6.0, "tech": "",
		"desc": "Carrion stink drags enemy units and insects to the centre and slows them 50% for 4 s."},
	"zombify": {"name": "Zombify", "cost": 60, "cd": 28.0, "radius": 4.5, "tech": "hypocreales",
		"desc": "Up to 4 enemy non-elite units become your Cordyceps Thralls."},
	"borer_swarm": {"name": "Agrilus Swarm", "cost": 70, "cd": 45.0, "radius": 8.0, "tech": "agrilus",
		"desc": "Cast on a tree: 7 jewel-beetle borers girdle it for 45 s, draining its vigor fast (oak, birch, ash; conifers resist). Kill the borers to save it. A tree that dies stands as a snag that breeds bark beetles."},
	"pandemic": {"name": "Pandemic", "cost": 90, "cd": 55.0, "radius": 10.0, "tech": "pandemic",
		"desc": "For 15 s, anything that dies in the area rises as your thrall."},
}


static func faction_color(f: int) -> Color:
	if f < 0 or f >= FACTIONS.size():
		return Color(0.62, 0.55, 0.42)
	return FACTIONS[f]["color"]


static func world_to_uv(p: Vector2) -> Vector2:
	return Vector2((p.x + HALF_W) / (HALF_W * 2.0), (p.y + HALF_D) / (HALF_D * 2.0))
