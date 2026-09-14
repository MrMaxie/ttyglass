# libvterm 0.3.3

This directory vendors the C source from the `v0.3.3` tag of
https://github.com/neovim/libvterm at commit
`9d6d2112335080312ef8c36667fa717ded4f7daf`.

The two `src/encoding/*.inc` lookup tables are deterministic generated files
produced from the adjacent upstream `.tbl` inputs by the tag's `tbl2inc_c.pl`
script. They are retained because package builds do not require Perl.

ttyglass compiles these files directly into each native executable. The
upstream MIT license is retained in `LICENSE`. `SHA256SUMS` records every
vendored build input so the exact source can be verified without network
access.
