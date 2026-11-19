"""Write assets/characters/human/CREDITS.md from the MakeHuman pack indexes.

    python3 tools/write_credits.py <assets/characters/human> <mpfb user data dir>
"""
import json, os, sys, glob

out_dir, data_dir = sys.argv[1], sys.argv[2]
meta = {}
for f in glob.glob(os.path.join(data_dir, "packs", "*.json")):
    try:
        for k, v in json.load(open(f)).items():
            meta[k] = v
    except Exception:
        pass
cat = json.load(open(os.path.join(out_dir, "catalog.json")))
rows = []
seen = set()
for g, b in cat["bodies"].items():
    for s in b["skins"]:
        rows.append(("skin", s["id"]))
for e in cat["eyes"]:
    rows.append(("eyes", e["id"]))
for g, slots in cat["items"].items():
    for slot, items in slots.items():
        for it in items:
            rows.append((slot, it["id"]))
lines = ["# Character asset credits", "",
         "Characters are generated with MakeHuman / MPFB2 (base mesh and system assets are CC0).",
         "Assets marked CC-BY require crediting the author, which this file does. Keep it with the game.", "",
         "| Type | Asset | Author | Licence | Source |", "| --- | --- | --- | --- | --- |"]
for t, n in rows:
    if (t, n) in seen:
        continue
    seen.add((t, n))
    m = meta.get(n, {})
    lic = m.get("license", "CC0" if n in meta or t in ("skin", "eyes") else "CC0 (MakeHuman system asset)")
    lines.append("| %s | %s | %s | %s | %s |" % (t, n, m.get("author", "MakeHuman team"), lic, m.get("source", "")))
cc_by = sorted({meta[n].get("author", "") for t, n in rows if meta.get(n, {}).get("license", "").upper().startswith("CC-BY")})
lines += ["", "**CC-BY authors to credit in the game:** " + ", ".join(a for a in cc_by if a)]
open(os.path.join(out_dir, "CREDITS.md"), "w").write("\n".join(lines) + "\n")
print("credits:", len(seen), "assets; CC-BY authors:", cc_by)
