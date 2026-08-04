package constants

Block :: enum u64 {
    Air,
    Grass1,
    Grass2,
    Grass3,
    Sand1,
    Blue,
    Brow,
}

PaletteMap :: struct {
    key:   Block,
    value: u32
}

BLOCK_PALETTE_MAP :: [7]PaletteMap{
    {.Air,    0x000000},
    {.Grass1, 0x3F9111},
    {.Grass2, 0x398210},
    {.Grass3, 0x3c8514},
    {.Sand1,  0xEBC634},
    {.Blue,  0x34a2c9},
    {.Brow,  0x7d450c},
}
