"""
Bake Tripnanza's customizable riders from MakeHuman assets (Blender + MPFB2).

Run (needs Blender 4.2+ with the MPFB extension and asset packs installed):
    blender --background --python tools/bake_characters.py -- <out_dir> [--quick]

Writes into <out_dir> (normally assets/characters/human):
    <gender>/body.glb              body + eyes/brows/lashes, game_engine rig,
                                   face shape keys, body-region vertex colours
    <gender>/<slot>_<id>.glb       each clothing / hair item fitted to that body
    skins/*.jpg, eyes/*.jpg        swappable textures
    catalog.json                   everything the game's customization menu lists
    CREDITS.md                     authors + licences of every asset used
"""
import bpy, bmesh, os, sys, json, re, shutil, math
from mathutils import kdtree, Vector

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService
from bl_ext.user_default.mpfb.services.assetservice import AssetService
from bl_ext.user_default.mpfb.services.locationservice import LocationService
from bl_ext.user_default.mpfb.services.objectservice import ObjectService

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "out")
QUICK = "--quick" in argv
TEX = 1024              # texture size in the game (keeps the repo small)

BODIES = {
    "male": {"gender": 1.0, "age": 0.5, "muscle": 0.6, "weight": 0.5, "height": 0.55, "proportions": 0.65,
             "cupsize": 0.5, "firmness": 0.5, "race": {"african": 0.33, "asian": 0.33, "caucasian": 0.34}},
    "female": {"gender": 0.0, "age": 0.5, "muscle": 0.55, "weight": 0.5, "height": 0.5, "proportions": 0.65,
               "cupsize": 0.5, "firmness": 0.6, "race": {"african": 0.33, "asian": 0.33, "caucasian": 0.34}},
}

# Face sliders: id, label, [(target base, has both sides)], each exported as
# incr/decr shape keys named  m:<id>:<incr|decr>:<n>
FACE = [
    ("fullness", "Face fullness", ["head/head-fat"]),
    ("head_width", "Head width", ["head/head-scale-horiz"]),
    ("jaw_width", "Jaw width", ["chin/chin-width"]),
    ("chin", "Chin", ["chin/chin-prominent"]),
    ("cheekbones", "Cheekbones", ["cheek/l-cheek-bones", "cheek/r-cheek-bones"]),
    ("nose_size", "Nose size", ["nose/nose-volume"]),
    ("nose_width", "Nose width", ["nose/nose-scale-horiz"]),
    ("nose_bridge", "Nose bridge", ["nose/nose-hump"]),
    ("mouth_width", "Mouth width", ["mouth/mouth-scale-horiz"]),
    ("lips", "Lip fullness", ["mouth/mouth-lowerlip-volume"]),
    ("eye_size", "Eye size", ["eyes/l-eye-scale", "eyes/r-eye-scale"]),
    ("ears", "Ear size", ["ears/l-ear-scale", "ears/r-ear-scale"]),
    ("brows", "Brow height", ["eyebrows/eyebrows-trans"]),
]

# Clothing slots by name keywords (first match wins). Items matching EXCLUDE
# are skipped (novelty / costume pieces that don't fit a snowboarder).
SLOTS = [
    ("eyewear", ["glasses", "goggle"]),
    ("gloves", ["glove"]),
    ("hat", ["hat", "cap", "beanie", "hood", "helmet"]),
    ("shoes", ["shoe", "boot", "sneaker", "trainer"]),
    ("bottom", ["pant", "trouser", "jean", "short", "skirt", "legging"]),
    ("top", ["shirt", "jacket", "hoodie", "sweat", "top", "tee", "sweater", "coat", "suit", "vest", "tunic", "blouse"]),
]
EXCLUDE = ["bag_on_head", "doc_ock", "3d_glasses", "maga", "genital", "underwear", "bikini", "lingerie", "bra",
           "disco", "ruffle", "swim", "xmas", "wig_bow", "feather", "don_quixote", "tie_tucked", "uniform", "emt",
           "harem", "boho", "sash", "tunic", "mma"]
SKIN_EXCLUDE = ["genital", "hairless", "uniform", "old_", "middle_aged", "makeup", "violet"]
# Curated picks that suit a snowboarder (asset folder names).
ITEMS = {
    "hair": ["short01", "short02", "short03", "short04", "cortu_short_messy_hair", "elvs_short_side_do",
             "elvs_maxwell_hair", "elvs_grump_hair", "elvs_keylth_hair", "afro01", "elvs_micky_afro",
             "elvs_braided_rows", "culturalibre_hair_01", "culturalibre_hair_05", "bob01", "bob02",
             "toigo_blunt_bob_with_bangs", "elvs_wavy_bob", "long01", "ponytail01", "braid01",
             "punkduck_alpha7_long", "elvs_lara_hair", "elvs_hazel_hair", "o4saken_curly01",
             "rehmanpolanski_hair_bun_brown", "cortu_shaggy_green_hair", "cortu_strawberry_cloud_hair"],
    "top": ["elvs_hooded_sweat_jacket1", "mindfront_lusekofta", "mindfront_knitted_sweater_01",
            "mindfront_knitted_sweater_02", "toigo_fisherman_sweater", "mindfront_cardigan_long_open_front",
            "female_sportsuit01", "male_worksuit01", "male_casualsuit01", "male_casualsuit03", "male_casualsuit05",
            "female_casualsuit01", "female_casualsuit02", "elvs_crude_t-shirt_male", "ews_striped_shirt",
            "namuhekam_male_polo_shirt", "janexx_old_female_sweater"],
    "bottom": ["cortu_cargo_pants", "toigo_wool_pants", "cortu_jeans_shorts"],
    "shoes": ["toigo_ankle_boots_male", "toigo_ankle_boots_female", "culturalibre_male_boots", "culturalibre_hero_boots_1",
              "culturalibre_heroine_boots_1", "shoes01", "shoes03", "shoes05"],
    "gloves": ["toigo_gloves_short", "toigo_gloves_medium", "culturalibre_hero-heroine_gloves_1", "culturalibre_hero-heroine_gloves_3"],
    "hat": ["culturalibre_motorcycle_helmet", "jujube_newsboy_cap", "fedora01", "joepal_xmas_cap"],
    "eyewear": ["kwnet_at_optical_glasses", "spamrakuen_sagerfrogs_glasses_01", "spamrakuen_sagerfrogs_glasses_03",
                "toigo_round_glasses_leopard", "frankyaye_glasses_library_male"],
}
SKINS = {
    "male": ["young_caucasian_male", "young_caucasian_male2", "young_african_male", "young_asian_male",
             "middleage_caucasian_male", "middleage_african_male", "middleage_asian_male"],
    "female": ["young_caucasian_female", "young_caucasian_female2", "young_african_female", "young_asian_female",
               "onlytheghosts_young_eurasian_female", "toigo_light_skin_female_freckles", "cutoff3d_indian_female_skin",
               "darthfurby_caucasian_female", "middleage_african_female", "middleage_asian_female"],
}
EYE_EXCLUDE = ["anime", "toon", "maid"]
if QUICK:
    ITEMS = {k: v[:2] for k, v in ITEMS.items()}
TEX_SLOT = {"body": 1024}   # everything else (hair included: it is dyed in game) 512
MAX_FACES = 12000            # heavier clothing/hair meshes are simplified

REGION_BONES = {
    "torso": ["pelvis", "spine_01", "spine_02", "spine_03"],
    "arms": ["clavicle", "upperarm", "lowerarm"],
    "legs": ["thigh", "calf"],
    "feet": ["foot", "ball"],
    "hands": ["hand", "thumb", "index", "middle", "ring", "pinky"],
    "head": ["neck", "head"],
}

credits = []


def log(*a):
    print("[bake]", *a, flush=True)


def read_meta(path):
    """Author / licence lines from an .mhclo/.mhmat file."""
    meta = {"author": "", "license": ""}
    try:
        with open(path, encoding="utf-8", errors="ignore") as f:
            for line in f:
                low = line.lower()
                if low.startswith("author"):
                    meta["author"] = line.split(None, 1)[1].strip() if len(line.split(None, 1)) > 1 else ""
                elif low.startswith("license"):
                    meta["license"] = line.split(None, 1)[1].strip() if len(line.split(None, 1)) > 1 else ""
    except Exception:
        pass
    return meta


def pretty(name):
    n = re.sub(r"^(elvs|culturalibre|toigo|punkduck|o4saken|grinsegold|cortu|joepal|jujube|kwnet|spamrakuen|aethelraed|learning|frankyaye|ews|drednicolson|mindfront|shirtsalot)_", "", name)
    n = n.replace("_", " ").replace("-", " ").strip()
    return n[:1].upper() + n[1:]


def reset():
    bpy.ops.wm.read_homefile(use_empty=True)


def make_body(gender):
    reset()
    # Helpers stay on the working mesh (clothes fit by vertex index); they are
    # stripped from the exported copy only.
    basemesh = HumanService.create_human(mask_helpers=True, detailed_helpers=True, extra_vertex_groups=True,
                                         feet_on_ground=True, scale=0.1, macro_detail_dict=BODIES[gender])
    TargetService.bake_targets(basemesh)
    rig = HumanService.add_builtin_rig(basemesh, "game_engine", import_weights=True)
    if rig is None:
        rig = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    return basemesh, rig


def add_bodyparts(basemesh):
    parts = []
    for sub, prefs in [("eyes", ["high-poly", "low-poly"]), ("eyebrows", ["eyebrow001", "eyebrow"]), ("eyelashes", ["eyelashes01", "eyelashes"])]:
        files = [str(p) for p in AssetService.list_mhclo_assets(sub)]
        pick = None
        for pref in prefs:
            pick = next((f for f in files if pref in os.path.basename(f).lower()), None)
            if pick:
                break
        if not pick and files:
            pick = files[0]
        if pick:
            obj = HumanService.add_mhclo_asset(pick, basemesh, asset_type=sub.capitalize(), subdiv_levels=0, material_type="MAKESKIN")
            parts.append(obj)
            log("bodypart", sub, os.path.basename(pick))
    return [p for p in parts if p]


def add_face_keys(basemesh):
    tdir = os.path.join(LocationService.get_mpfb_data("targets"))
    morphs = []
    if basemesh.data.shape_keys is None:
        basemesh.shape_key_add(name="Basis", from_mix=False)
    for fid, label, bases in FACE:
        ok = False
        for n, base in enumerate(bases):
            for d1, d2, tag in [("incr", "decr", None)]:
                pass
            for direction, alt in [("incr", "up"), ("decr", "down")]:
                cand = [base + "-" + direction, base + "-" + alt]
                path = None
                for c in cand:
                    p = os.path.join(tdir, c + ".target.gz")
                    if os.path.exists(p):
                        path = p
                if path is None:
                    continue
                key_name = "m:%s:%s:%d" % (fid, direction, n)
                TargetService.load_target(basemesh, path, weight=0.0, name=key_name)
                ok = True
        if ok:
            morphs.append({"id": fid, "name": label})
    for kb in basemesh.data.shape_keys.key_blocks:
        kb.value = 0.0
    return morphs


def paint_regions(basemesh, rig):
    """Vertex colour = body region (R torso, G arms, B legs, A feet); UV2.x hands, UV2.y head."""
    me = basemesh.data
    names = {g.index: g.name for g in basemesh.vertex_groups}
    region_of = {}
    for v in me.vertices:
        best, bw = None, 0.0
        for g in v.groups:
            if g.weight > bw and names.get(g.group, "") in [b.name for b in rig.data.bones]:
                best, bw = names[g.group], g.weight
        r = "torso"
        if best:
            for reg, keys in REGION_BONES.items():
                if any(best.startswith(k) for k in keys):
                    r = reg
                    break
        region_of[v.index] = r
    if "Region" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Region"])
    col = me.color_attributes.new(name="Region", type="FLOAT_COLOR", domain="POINT")
    for v in me.vertices:
        r = region_of[v.index]
        col.data[v.index].color = (1.0 if r == "torso" else 0.0, 1.0 if r == "arms" else 0.0,
                                   1.0 if r == "legs" else 0.0, 1.0 if r == "feet" else 0.0)
    me.color_attributes.active_color = col
    uv2 = me.uv_layers.new(name="Regions")
    for loop in me.loops:
        r = region_of[loop.vertex_index]
        uv2.data[loop.index].uv = (1.0 if r == "hands" else 0.0, 1.0 if r == "head" else 0.0)
    return region_of


def shrink_images(objs, tex=TEX):
    seen = set()
    for o in objs:
        for slot in o.material_slots:
            m = slot.material
            if not m or not m.use_nodes:
                continue
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and n.image.name not in seen:
                    seen.add(n.image.name)
                    img = n.image
                    try:
                        if max(img.size) > tex:
                            img.scale(min(tex, img.size[0]), min(tex, img.size[1]))
                        img.pack()
                    except Exception as e:
                        log("image", img.name, e)


def body_export_copy(basemesh):
    """Duplicate of the body without helper geometry or mask modifiers."""
    dup = basemesh.copy()
    dup.data = basemesh.data.copy()
    bpy.context.collection.objects.link(dup)
    vg = dup.vertex_groups.get("body")
    if vg:
        bm = bmesh.new()
        bm.from_mesh(dup.data)
        deform = bm.verts.layers.deform.verify()
        kill = [v for v in bm.verts if vg.index not in v[deform]]
        bmesh.ops.delete(bm, geom=kill, context="VERTS")
        bm.to_mesh(dup.data)
        bm.free()
    for m in list(dup.modifiers):
        if m.type != "ARMATURE":
            dup.modifiers.remove(m)
    dup.name = "Body"
    return dup


def simplify(obj):
    """Decimate very dense meshes (keeps UVs and skin weights)."""
    faces = len(obj.data.polygons)
    if faces <= MAX_FACES:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("Simplify", "DECIMATE")
    mod.ratio = MAX_FACES / faces
    while obj.modifiers[0] != mod:
        bpy.ops.object.modifier_move_up(modifier=mod.name)
    if obj.data.shape_keys:
        obj.shape_key_clear()
    bpy.ops.object.modifier_apply(modifier=mod.name)
    log("simplified", obj.name, faces, "->", len(obj.data.polygons))


def export(objs, rig, path, tex=TEX):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs + [rig]:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    shrink_images(objs, tex)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_morph=True, export_morph_normal=False,
                              export_animations=False, export_yup=True, export_vertex_color="ACTIVE",
                              export_image_format="JPEG", export_jpeg_quality=85)
    log("exported", os.path.relpath(path, OUT), "%.1f MB" % (os.path.getsize(path) / 1048576))


def coverage(basemesh, region_of, item):
    """Which body regions an item covers (>80% of region vertices within 2.5 cm)."""
    deps = bpy.context.evaluated_depsgraph_get()
    ev = item.evaluated_get(deps)
    me = ev.to_mesh()
    kd = kdtree.KDTree(len(me.vertices))
    for i, v in enumerate(me.vertices):
        kd.insert(item.matrix_world @ v.co, i)
    kd.balance()
    ev.to_mesh_clear()
    vg = basemesh.vertex_groups.get("body")
    counts, hits = {}, {}
    for v in basemesh.data.vertices:
        if vg is not None and not any(g.group == vg.index for g in v.groups):
            continue
        r = region_of.get(v.index, "torso")
        counts[r] = counts.get(r, 0) + 1
        co, idx, dist = kd.find(basemesh.matrix_world @ v.co)
        if co is not None and dist < 0.06:
            hits[r] = hits.get(r, 0) + 1
    out = []
    for r in ["torso", "arms", "legs", "feet", "hands"]:
        if counts.get(r, 0) and hits.get(r, 0) / counts[r] > 0.7:
            out.append(r)
    return out


def classify(name):
    low = name.lower()
    if any(x in low for x in EXCLUDE):
        return None
    for slot, keys in SLOTS:
        if any(k in low for k in keys):
            return slot
    return None


def list_items():
    found = {}
    for sub in ["hair", "clothes"]:
        for p in AssetService.list_mhclo_assets(sub):
            found[os.path.splitext(os.path.basename(str(p)))[0]] = str(p)
    items = {}
    for slot, names in ITEMS.items():
        items[slot] = [(n, found[n]) for n in names if n in found]
        missing = [n for n in names if n not in found]
        if missing:
            log("missing", slot, missing)
    return items


def skins_for(gender):
    found = {os.path.splitext(os.path.basename(str(p)))[0]: str(p) for p in AssetService.list_mhmat_assets("skins")}
    return [(n, found[n]) for n in SKINS[gender] if n in found]


def texture_from_mhmat(path, key="diffuseTexture"):
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            if line.split() and line.split()[0] == key:
                return os.path.join(os.path.dirname(path), line.split(None, 1)[1].strip())
    return None


def save_tex(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img = bpy.data.images.load(src)
    if max(img.size) > TEX:
        img.scale(min(TEX, img.size[0]), min(TEX, img.size[1]))
    img.filepath_raw = dst
    img.file_format = "JPEG"
    bpy.context.scene.render.image_settings.quality = 88
    img.save()
    bpy.data.images.remove(img)


def main():
    os.makedirs(OUT, exist_ok=True)
    AssetService.update_all_asset_lists()
    catalog = {"bodies": {}, "items": {}, "eyes": [], "credits": []}
    all_items = list_items()
    log("items:", {k: len(v) for k, v in all_items.items()})
    # Eye colours.
    for p in sorted(AssetService.list_mhmat_assets("eyes"), key=lambda x: str(x)):
        n = os.path.splitext(os.path.basename(str(p)))[0]
        if any(x in n.lower() for x in EYE_EXCLUDE):
            continue
        tex = texture_from_mhmat(str(p))
        if tex and os.path.exists(tex):
            dst = os.path.join(OUT, "eyes", n + ".jpg")
            save_tex(tex, dst)
            catalog["eyes"].append({"id": n, "name": pretty(n), "albedo": "eyes/%s.jpg" % n})
    for gender in BODIES:
        log("=== body", gender)
        basemesh, rig = make_body(gender)
        parts = add_bodyparts(basemesh)
        skins = skins_for(gender)
        if skins:
            HumanService.set_character_skin(skins[0][1], basemesh, skin_type="MAKESKIN")
        morphs = add_face_keys(basemesh)
        region_of = paint_regions(basemesh, rig)
        body = body_export_copy(basemesh)
        export([body] + parts, rig, os.path.join(OUT, gender, "body.glb"))
        bpy.data.objects.remove(body, do_unlink=True)
        skin_list = []
        for n, p in skins[: (2 if QUICK else 12)]:
            tex = texture_from_mhmat(p)
            if not tex or not os.path.exists(tex):
                continue
            dst = os.path.join(OUT, "skins", n + ".jpg")
            if not os.path.exists(dst):
                save_tex(tex, dst)
            meta = read_meta(p)
            credits.append(("skin", n, meta))
            skin_list.append({"id": n, "name": pretty(n), "albedo": "skins/%s.jpg" % n})
        catalog["bodies"][gender] = {"body": gender + "/body.glb", "skins": skin_list, "morphs": morphs}
        catalog["items"][gender] = {}
        for slot, lst in all_items.items():
            catalog["items"][gender][slot] = []
            for n, p in lst:
                try:
                    obj = HumanService.add_mhclo_asset(p, basemesh, asset_type="Hair" if slot == "hair" else "Clothes",
                                                       subdiv_levels=0, material_type="MAKESKIN")
                except Exception as e:
                    log("FAILED", n, e)
                    continue
                if obj is None:
                    continue
                for m in list(basemesh.modifiers):
                    if m.type == "MASK" and m.name != "Hide helpers":
                        basemesh.modifiers.remove(m)
                hides = [] if slot in ("hair", "eyewear", "hat") else coverage(basemesh, region_of, obj)
                if slot == "shoes" and "feet" not in hides:
                    hides.append("feet")
                if slot == "gloves" and "hands" not in hides:
                    hides.append("hands")
                simplify(obj)
                path = os.path.join(OUT, gender, "%s_%s.glb" % (slot, n))
                obj.name = "%s_%s" % (slot, n)
                export([obj], rig, path, TEX_SLOT.get(slot, 512))
                alpha = slot == "hair" or any(m.material and m.material.blend_method != "OPAQUE" for m in obj.material_slots)
                catalog["items"][gender][slot].append({"id": n, "name": pretty(n), "file": "%s/%s_%s.glb" % (gender, slot, n),
                                                       "hides": hides, "alpha": alpha})
                if gender == "male":
                    credits.append((slot, n, read_meta(p)))
                bpy.data.objects.remove(obj, do_unlink=True)
    with open(os.path.join(OUT, "catalog.json"), "w") as f:
        json.dump(catalog, f, indent=1)
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("# Character asset credits\n\nGenerated with MakeHuman / MPFB2 (CC0 base mesh and system assets).\n\n")
        f.write("| Type | Asset | Author | Licence |\n| --- | --- | --- | --- |\n")
        for t, n, meta in credits:
            f.write("| %s | %s | %s | %s |\n" % (t, n, meta.get("author", ""), meta.get("license", "")))
    # Proper credits from the pack indexes (author / licence / source).
    import subprocess
    subprocess.run([sys.executable if not sys.executable.endswith("blender") else "python3",
                    os.path.join(os.path.dirname(__file__), "write_credits.py"), OUT, LocationService.get_user_data()])
    log("done")


main()
