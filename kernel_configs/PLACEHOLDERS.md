# Placeholder stock configs

Five build targets have no reachable stock firmware. Rather than ship builds that expose the real build config,
each gets a copy of the closest available real stock config, prefixed with a 4-line `# PLACEHOLDER` header.
Replace them when the device's own firmware or `/proc/config.gz` becomes available.

| file | copied from | kernel tag | why |
|---|---|---|---|
| `a14/OP-ACE_stock_defconfig` | `a14/OP-ACE-RACE` | `5.10.209-android12-9-o-g149ffe97838f` | MTK 5.10 a14 sibling; the original Ace (PGBM10) ships a 4.14.186 kernel, so no 5.10 stock exists for it |
| `a15/OP-ACE_stock_defconfig` | `a15/OP-ACE-RACE` | `5.10.236-android12-9-o-g38e2c85bc7af` | MTK 5.10 a15 sibling, same reasoning as a14 |
| `a15/OP-NORD-N30-SE_stock_defconfig` | `a16/OP-NORD-6` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | closest 6.6 / android15 Qualcomm config without HMBIRD; Nord-family sibling |
| `a16/OP-N6X_stock_defconfig` | `a16/OP-N6` | `5.15.197-android13-8-o-g00d4e8e246c3` | same SoC (MT6835); OnePlusOSS defconfig for n6x is byte-identical to n6 |
| `a16/OP-TURBO-6X_stock_defconfig` | `a16/OP-NORD-CE6-LITE` | `6.1.157-android14-11-o-gc2dad16af736` | closest MTK 6.1 config available (MT6878 vs MT6835); Turbo 6X model code unpublished |
