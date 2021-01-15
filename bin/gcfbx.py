# gcfbx.py - Automate new FBX model rendering for NNT:GC
# Use within meriodasu.sh
# Author: calmadios, 2020
# License: MIT

import bpy
import sys
import os.path

argv = sys.argv
argv = argv[argv.index("--") + 1:]

in_dir = argv[0]
out_dir = argv[1]
hero = argv[2]
skin = argv[3]

hero_body = 'hero_' + hero + '_body_' + skin
hero_head = 'hero_' + hero + '_head_' + skin
hero_weap = 'weapon_' + hero + '_' + skin

body_present = os.path.isfile(in_dir + '/' + hero_body + '.fbx')
head_present = os.path.isfile(in_dir + '/' + hero_head + '.fbx')
weap_present = os.path.isfile(in_dir + '/' + hero_weap + '.fbx')

if not body_present and not head_present and not weap_present:
    sys.exit(1)

# Clean initial collection
scc = bpy.context.scene.collection.children
for c in scc:
    scc.unlink(c)

boss_units = {
    'demon_dragon', 'demon_king', 'supreme_deity', 'onion_demon', 'melascula_snake'
}
big_units = {
    'escanor', 'escanor_one', 'galland'
}

# Head corrections (usually needed)
off_head_coord = (0, 0, 0)
off_head_coord_db = {
    'arthur': (-0.865, 0.01, -0.03),    # OK
    'demon_king': (-4.75, 0, 0),        # OK
    'elizabeth': (-0.96, 0, -0.02),     # OK
    'escanor_one': (-1.45, 0, 0),       # needs strong backface culling, head is without mat (assert error in import)
    'elaine_wing': (-0.785, 0, -0.01),  # OK
    'goddess_ludociel': (-1.125, 0, 0), # OK
    'liliahawaken': (0, 0, 0),          # weapon is always rotated (mult axii) + moved in weird ways
    'meliodas': (-0.63, 0, -0.03),      # OK
    'nanashi': (-1.025, 0, -0.01),      # OK
    'supreme_deity': (-3.8, 0, 0)       # OK
}
if hero in off_head_coord_db:
    off_head_coord = off_head_coord_db[hero]
    
# Body corrections (rare, handle on per case basis)
off_body_coord = (0, 0, 0)
off_body_rotation = (0, 0, 0)
if hero == 'skeleton_normal' and skin == '0050':
    off_body_coord = (2.055, 0, 0)
if hero == 'elizabeth' and skin == '0052':
    off_body_rotation = (1.5708, 0, 0)
if hero == 'melascula_snake':
    if skin == '0001':
        off_body_rotation = (0, 0, -1.5708)
        off_body_coord = (4.5, 0, 0)
    if skin == '0002':
        off_body_rotation = (0, 0, -1.5708)

# Import FBXs
if body_present:
    bpy.ops.import_scene.fbx(filepath = in_dir + '/' + hero_body + '.fbx', global_scale = 100)
if head_present:
    bpy.ops.import_scene.fbx(filepath = in_dir + '/' + hero_head + '.fbx', global_scale = 100)
if weap_present:
    bpy.ops.import_scene.fbx(filepath = in_dir + '/' + hero_weap + '.fbx', global_scale = 100)

if body_present:
    bpy.data.objects[hero_body].rotation_euler = (off_body_rotation[0] + 1.5708, off_body_rotation[1], off_body_rotation[2])
    bpy.data.objects[hero_body].location = (off_body_coord[0], off_body_coord[1], off_body_coord[2])

# Correct head
if head_present:
    bpy.data.objects[hero_head].rotation_euler = (0, 0, -1.5708)
    bpy.data.objects[hero_head].location = off_head_coord

# Correct weapon
if weap_present:
    bpy.data.objects[hero_weap].rotation_euler = (0, 0, -1.5708)
    bpy.data.objects[hero_weap].location = off_head_coord

# Export as one FBX model
#bpy.ops.export_scene.fbx(filepath =  out_dir + '/fbx/hero_' + hero + '_' + skin + '.fbx')

# Create camera and lighting
camera_data = bpy.data.cameras.new("camera_data")
light_data = bpy.data.lights.new(name="sun_data", type='SUN')

# Set basic lighting
light_data.energy = 5
sun = bpy.data.objects.new(name="sun", object_data=light_data)
sun.location = (2.5, -6, 2.5)

# Various modes for camera and light
unit_default_camera = (0.0,  -6.5, 1.00)
unit_big_camera     = (0.0,  -9.0, 1.50)
unit_default_sun    = (2.5,  -6.0, 2.50)
boss_default_camera = (0.0,  -7.5, 3.00)
boss_low_camera     = (0.0, -10.0, 1.50)
boss_tall_camera    = (0.0, -11.0, 4.50)
boss_tall_sun       = (2.5,  -6.0, 7.50)

# Adapt camera for current unit
if not hero in boss_units:
    camera_data.lens = 50
    camera = bpy.data.objects.new("camera", camera_data)
    camera.location = unit_big_camera if hero in big_units else unit_default_camera
else:
    camera_data.lens = 18
    camera = bpy.data.objects.new("camera", camera_data)
    camera.location = boss_default_camera
    if hero == 'demon_king' or hero == 'supreme_deity':
        camera.location = boss_tall_camera
        sun.location = boss_tall_sun
    if hero == 'melascula_snake':
        camera.location = boss_low_camera

# Set rotation and apply
camera.rotation_euler = (1.5708, 0, 0)
sun.rotation_euler = (1.39626, 0.261799, 0.349066)
bpy.context.collection.objects.link(camera)
bpy.context.collection.objects.link(sun)

# Setup view
for area in bpy.context.screen.areas:
    if area.type == 'VIEW_3D':
        for space in area.spaces:
            if space.type == 'VIEW_3D':
                space.overlay.show_overlays = False
                space.shading.type = 'MATERIAL'
                ctx = bpy.context.copy()
                ctx['area'] = area
                ctx['space'] = space
                ctx['region'] = area.regions[-1]
                break

# Render settings
ctx['scene'].camera = camera
ctx['scene'].render.image_settings.file_format = 'PNG'

# Front
ctx['scene'].render.filepath = out_dir + '/hero_' + hero + '_' + skin + '_00.png'
bpy.ops.render.render(ctx, write_still=True, use_viewport=True)

# Right
if head_present:
    bpy.data.objects[hero_head].location = (0, 0, 0)
    bpy.data.objects[hero_head].rotation_euler = (0, 0, 0)
    bpy.data.objects[hero_head].location = (off_head_coord[1], off_head_coord[0], off_head_coord[2])
if weap_present:
    bpy.data.objects[hero_weap].location = (0, 0, 0)
    bpy.data.objects[hero_weap].rotation_euler = (0, 0, 0)
    bpy.data.objects[hero_weap].location = (off_head_coord[1], off_head_coord[0], off_head_coord[2])
if body_present:
    bpy.data.objects[hero_body].location = (0, 0, 0)
    bpy.data.objects[hero_body].rotation_euler = (off_body_rotation[0] + 1.5708, off_body_rotation[1], off_body_rotation[2] + 1.5708)
    bpy.data.objects[hero_body].location = (off_body_coord[1], off_body_coord[0], off_body_coord[2])
ctx['scene'].render.filepath = out_dir + '/hero_' + hero + '_' + skin + '_01.png'
bpy.ops.render.render(ctx, write_still=True, use_viewport=True)

# Back
if head_present:
    bpy.data.objects[hero_head].location = (0, 0, 0)
    bpy.data.objects[hero_head].rotation_euler = (0, 0, 1.5708)
    bpy.data.objects[hero_head].location = (-off_head_coord[0], -off_head_coord[1], off_head_coord[2])
if weap_present:
    bpy.data.objects[hero_weap].location = (0, 0, 0)
    bpy.data.objects[hero_weap].rotation_euler = (0, 0, 1.5708)
    bpy.data.objects[hero_weap].location = (-off_head_coord[0], -off_head_coord[1], off_head_coord[2])
if body_present:
    bpy.data.objects[hero_body].location = (0, 0, 0)
    bpy.data.objects[hero_body].rotation_euler = (off_body_rotation[0] + 1.5708, off_body_rotation[1], off_body_rotation[2] + 3.1415)
    bpy.data.objects[hero_body].location = (-off_body_coord[0], -off_body_coord[1], off_body_coord[2])
ctx['scene'].render.filepath = out_dir + '/hero_' + hero + '_' + skin + '_02.png'
bpy.ops.render.render(ctx, write_still=True, use_viewport=True)

# Left
if head_present:
    bpy.data.objects[hero_head].location = (0, 0, 0)
    bpy.data.objects[hero_head].rotation_euler = (0, 0, 3.1415)
    bpy.data.objects[hero_head].location = (-off_head_coord[1], -off_head_coord[0], off_head_coord[2])
if weap_present:
    bpy.data.objects[hero_weap].location = (0, 0, 0)
    bpy.data.objects[hero_weap].rotation_euler = (0, 0, 3.1415)
    bpy.data.objects[hero_weap].location = (-off_head_coord[1], -off_head_coord[0], off_head_coord[2])
if body_present:
    bpy.data.objects[hero_body].location = (0, 0, 0)
    bpy.data.objects[hero_body].rotation_euler = (off_body_rotation[0] + 1.5708, off_body_rotation[1], off_body_rotation[2] + -1.5708)
    bpy.data.objects[hero_body].location = (-off_body_coord[1], -off_body_coord[0], off_body_coord[2])
ctx['scene'].render.filepath = out_dir + '/hero_' + hero + '_' + skin + '_03.png'
bpy.ops.render.render(ctx, write_still=True, use_viewport=True)

bpy.ops.wm.quit_blender()