# Example texture pack

Start a pack by copying this layout:

```
my_pack/
├── pack.json          {"name": "My Pack", "resolution": 64}
└── textures/
    └── stone.png      (+ optional stone_h.png / stone_n.png / stone_r.png)
```

Zip the `my_pack` folder and import it from Settings → Texture packs. Any texture you
leave out keeps the built-in look. The full list of texture names and the format are
in [docs/TEXTURE_PACKS.md](../docs/TEXTURE_PACKS.md).

`python3 tools/make_example_pack.py` generates a ready-made test pack at
`build/example_pack.zip`.
