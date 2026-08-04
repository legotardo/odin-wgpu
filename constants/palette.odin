package constants

Block :: enum u64 {
    Air,
    Grass1,
    Grass2,
    Grass3,
    Sand1,
}

PaletteMap :: struct {
    key:   Block,
    value: u32
}

BLOCK_PALETTE_MAP :: [5]PaletteMap{
    {.Air,    0x000000},
    {.Grass1, 0x3F9111},
    {.Grass2, 0x398210},
    {.Grass3, 0x3c8514},
    {.Sand1,  0xEBC634},
}
