# Saman video segment (0:30-1:15)

From 0:30 to 1:15, I will explain the cache storage side of our design. The cache holds 1 KB and uses 16-byte blocks, so 1 KB divided by 16 B gives 64 lines. Therefore the index needs log2(64), or 6 bits. The block offset needs log2(16), or 4 bits: two bits select one of four 32-bit words and two select a byte within that word. Starting with a 32-bit address, the remaining tag is 32 minus 6 minus 4, or 22 bits. The block diagram feeds these fields to the tag, valid, and data RAMs; their outputs support line lookup and word selection.

- `addr_decode` splits an address into tag, index, word-select, byte-offset, and an aligned block-base address.
- `tag_ram` stores one 22-bit tag per line, while `valid_ram` stores and reset-clears the corresponding validity bit.
- `data_ram` stores four independently addressed 32-bit words for every cache line.
