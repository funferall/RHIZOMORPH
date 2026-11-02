# Puffball Bomber

Morel Hollow area bombardment unit based on `reference_images/morel_hollow_roster.jpg`: a textured cream puffball, four short segmented legs and a raised dark spore vent. One surface per LOD: 37,312, 15,728 and 5,568 triangles (close, battle and distant). A shared albedo and normal atlas supplies the skin.

The shader animates alternating steps and a brief compression/recoil on firing, using the game clock. Leg roots follow the body while toes move together and remain grounded through the planted portion of each stride. These motions are shader driven, not skeletal GLB clips. A directional spore puff and the existing lobbed projectile emerge from the vent; the original damage, radius, cooldown and targeting remain in the simulation. HUD portraits use the close LOD.

Rebuild and inspect (Blender 4.2 and Godot 4.7.2):

```powershell
blender -b --factory-startup -P tools/blender/bomber_build.py
godot --headless --path . --editor --import --quit
godot --path . --script tools/art/render_unit.gd -- --unit=bomber --frames=32
godot --path . --script tools/art/ingame_unit.gd -- --unit=bomber
godot --headless --path . --script tools/tests/court_units.gd
```

`bomber_hero.png`, `bomber_ingame_close.png`, `attack.gif` and `walk.gif` are engine captures. Frame directories are ignored. Integration tests check LOD ordering, match and portrait mesh usage, oriented vent origin, recoil trigger, arc and damage, and splash damage against two targets. The Court test reports seven ObjectDB instances at shutdown.
