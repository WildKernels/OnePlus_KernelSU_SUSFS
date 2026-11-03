# Stock kernel config index

Gathered **2026-11-03** — 104 configs, one per (Android release × build target) in `configs/`.
Each was extracted from the kernel `Image` inside the device's own OTA `boot.img` (IKCFG blob); the 5 placeholders are marked ⚠ and listed in `PLACEHOLDERS.md`.

| | |
|---|---|
| configs | 104 (a14 13, a15 40, a16 51) |
| real (from boot.img) | 99 |
| placeholders | 5 |
| kernel lines | 5.10 (26), 5.15 (15), 6.1 (34), 6.6 (21), 6.12 (8) |
| last updated | 2026-11-03 |

## By kernel line

| line | configs | sublevels seen |
|---|---|---|
| 5.10 | 26 | 149, 168, 209, 226, 236, 246 |
| 5.15 | 15 | 123, 167, 180, 197 |
| 6.1 | 34 | 57, 75, 115, 118, 128, 141, 157 |
| 6.6 | 21 | 30, 57, 66, 118 |
| 6.12 | 8 | 38, 58, 69 |

## Every config

| release | model | stock kernel (from boot.img) | config file | firmware |
|---|---|---|---|---|
| a14 | `OP-ACE` ⚠ | `5.10.209-android12-9-o-g815b180d5b8a` | `a14/OP-ACE_stock_defconfig` | copy of a14/OP-ACE-RACE |
| a14 | `OP-ACE-2V` | `5.10.209-android12-9-o-g8c421b8d3d52` | `a14/OP-ACE-2V_stock_defconfig` |  |
| a14 | `OP-ACE-3-PRO` | `6.1.75-android14-11-o-g7cddc8f99e91` | `a14/OP-ACE-3-PRO_stock_defconfig` |  |
| a14 | `OP-ACE-RACE` | `5.10.209-android12-9-o-g815b180d5b8a` | `a14/OP-ACE-RACE_stock_defconfig` |  |
| a14 | `OP-NORD-3` | `5.10.209-android12-9-o-g8c421b8d3d52` | `a14/OP-NORD-3_stock_defconfig` | CPH2493_14.0.0.570(EX01) |
| a14 | `OP-PAD-GO` | `5.10.168-android12-9-o-g200cfbceef32` | `a14/OP-PAD-GO_stock_defconfig` |  |
| a14 | `OP-PAD-MT6983` | `5.10.149-android12-9-o-g55d4ce7d4557` | `a14/OP-PAD-MT6983_stock_defconfig` |  |
| a14 | `OP-PAD-PRO` | `6.1.75-android14-11-o-gdbbbe9ebaaa8` | `a14/OP-PAD-PRO_stock_defconfig` |  |
| a14 | `OP10pro` | `5.10.209-android12-9-o-g9dbebb7bc3d8` | `a14/OP10pro_stock_defconfig` | NE2213_14.0.0.940(EX01) |
| a14 | `OP10r` | `5.10.209-android12-9-o-g815b180d5b8a` | `a14/OP10r_stock_defconfig` | CPH2411_15.0.0.700(EX01) |
| a14 | `OP11` | `5.15.123-android13-8-00766-gf04dea8b48fa` | `a14/OP11_stock_defconfig` | CPH2449_14.0.0.833(EX01) |
| a14 | `OP11r` | `5.10.209-android12-9-o-g8ba99bedf63b` | `a14/OP11r_stock_defconfig` | CPH2487_14.0.0.810(EX01) |
| a14 | `OP12` | `6.1.57-android14-11-o-ga23ceff5d55d` | `a14/OP12_stock_defconfig` | CPH2581_14.0.0.850(EX01) |
| a15 | `OP-ACE` ⚠ | `5.10.236-android12-9-o-g38e2c85bc7af` | `a15/OP-ACE_stock_defconfig` | copy of a15/OP-ACE-RACE |
| a15 | `OP-ACE-2` | `5.10.226-android12-9-o-gbf90590695a1` | `a15/OP-ACE-2_stock_defconfig` |  |
| a15 | `OP-ACE-2-PRO` | `5.15.167-android13-8-o-01144-gd83a4482a19d` | `a15/OP-ACE-2-PRO_stock_defconfig` |  |
| a15 | `OP-ACE-2V` | `5.10.226-android12-9-o-g104a939c0e3e` | `a15/OP-ACE-2V_stock_defconfig` |  |
| a15 | `OP-ACE-3` | `5.15.167-android13-8-o-01144-gdc8278c1c5f9` | `a15/OP-ACE-3_stock_defconfig` |  |
| a15 | `OP-ACE-3-PRO` | `6.1.118-android14-11-o-g1b63040d0a34` | `a15/OP-ACE-3-PRO_stock_defconfig` |  |
| a15 | `OP-ACE-3V` | `6.1.118-android14-11-o-ge56ebf48182b` | `a15/OP-ACE-3V_stock_defconfig` |  |
| a15 | `OP-ACE-5` | `6.1.118-android14-11-o-g778e4490e346` | `a15/OP-ACE-5_stock_defconfig` |  |
| a15 | `OP-ACE-5-PRO` | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a15/OP-ACE-5-PRO_stock_defconfig` |  |
| a15 | `OP-ACE-5-RACE` | `6.1.115-android14-11-o-gae6c35f42659` | `a15/OP-ACE-5-RACE_stock_defconfig` |  |
| a15 | `OP-ACE-5-ULTRA` | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a15/OP-ACE-5-ULTRA_stock_defconfig` |  |
| a15 | `OP-ACE-RACE` | `5.10.236-android12-9-o-g38e2c85bc7af` | `a15/OP-ACE-RACE_stock_defconfig` |  |
| a15 | `OP-NORD-3` | `5.10.236-android12-9-o-g17fab92a617d` | `a15/OP-NORD-3_stock_defconfig` | CPH2493_15.0.0.1601(EX01) |
| a15 | `OP-NORD-4` | `6.1.118-android14-11-o-g2f4ade3e433d` | `a15/OP-NORD-4_stock_defconfig` | CPH2663_15.0.0.1301(EX01) |
| a15 | `OP-NORD-4-CE` | `5.15.167-android13-8-o-01144-g371cef69d4b6` | `a15/OP-NORD-4-CE_stock_defconfig` | CPH2613_15.0.0.1301(EX01) |
| a15 | `OP-NORD-5` | `6.1.118-android14-11-o-g5223d7db527e` | `a15/OP-NORD-5_stock_defconfig` | CPH2709_15.0.2.604(EX01) |
| a15 | `OP-NORD-CE-5` | `6.1.115-android14-11-o-gae6c35f42659` | `a15/OP-NORD-CE-5_stock_defconfig` |  |
| a15 | `OP-NORD-CE4-LITE` | `6.1.118-android14-11-o-g36c82242b58f` | `a15/OP-NORD-CE4-LITE_stock_defconfig` | CPH2621_15.0.0.1360(EX01) |
| a15 | `OP-NORD-N30-SE` ⚠ | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a15/OP-NORD-N30-SE_stock_defconfig` | copy of a16/OP-NORD-6 |
| a15 | `OP-OPEN` | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a15/OP-OPEN_stock_defconfig` | CPH2551_15.0.0.860(EX01) |
| a15 | `OP-PAD-2-PRO` | `6.6.57-android15-8-g7b1f455c7143-ab13591283-4k` | `a15/OP-PAD-2-PRO_stock_defconfig` |  |
| a15 | `OP-PAD-2-SM8650` | `6.1.118-android14-11-o-g2b8edc801b38` | `a15/OP-PAD-2-SM8650_stock_defconfig` | OPD2403_15.0.0.1301(EX01) |
| a15 | `OP-PAD-3-MT6897` | `6.1.128-android14-11-o-g415ded6ed906` | `a15/OP-PAD-3-MT6897_stock_defconfig` |  |
| a15 | `OP-PAD-3-SM8750` | `6.6.57-android15-8-g7b1f455c7143-ab13591283-4k` | `a15/OP-PAD-3-SM8750_stock_defconfig` | OPD2415_15.0.1.801(EX01) |
| a15 | `OP-PAD-LITE` | `5.10.236-android12-9-o-gfaf67edbfb7d` | `a15/OP-PAD-LITE_stock_defconfig` | OPD2480_16.0.5.1301(EX01) |
| a15 | `OP-PAD-MT6983` | `5.10.149-android12-9-o-g55d4ce7d4557` | `a15/OP-PAD-MT6983_stock_defconfig` |  |
| a15 | `OP-PAD-PRO` | `6.1.118-android14-11-o-g2b8edc801b38` | `a15/OP-PAD-PRO_stock_defconfig` |  |
| a15 | `OP10pro` | `5.10.226-android12-9-o-gb4f7990ee2d5` | `a15/OP10pro_stock_defconfig` | NE2213_15.0.0.1302(EX01) |
| a15 | `OP10r` | `5.10.209-android12-9-o-g815b180d5b8a` | `a15/OP10r_stock_defconfig` | CPH2411_15.0.0.700(EX01) |
| a15 | `OP10t` | `5.10.236-android12-9-o-g55571f3ffcfa` | `a15/OP10t_stock_defconfig` | CPH2415_15.0.0.1901(EX01) |
| a15 | `OP11` | `5.15.167-android13-8-o-01144-g65859ad20d1b` | `a15/OP11_stock_defconfig` | CPH2449_15.0.0.862(EX01) |
| a15 | `OP11r` | `5.10.226-android12-9-o-gbf90590695a1` | `a15/OP11r_stock_defconfig` | CPH2487_15.0.0.870(EX01) |
| a15 | `OP12` | `6.1.118-android14-11-o-g818f2506c9e7` | `a15/OP12_stock_defconfig` | CPH2581_15.0.0.863(EX01) |
| a15 | `OP12r` | `5.15.167-android13-8-o-01144-g55430422533e` | `a15/OP12r_stock_defconfig` | CPH2609_15.0.0.870(EX01) |
| a15 | `OP13` | `6.6.30-android15-8-g0261dbe3cf7e-ab12786384-4k` | `a15/OP13_stock_defconfig` | CPH2653_15.0.0.703(EX01) |
| a15 | `OP13-CPH` | `6.6.30-android15-8-g0261dbe3cf7e-ab12786384-4k` | `a15/OP13-CPH_stock_defconfig` | CPH2653_15.0.0.703(EX01) |
| a15 | `OP13-PJZ` | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a15/OP13-PJZ_stock_defconfig` |  |
| a15 | `OP13S` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a15/OP13S_stock_defconfig` | CPH2723_17.0.0.101(EX01) |
| a15 | `OP13T` | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a15/OP13T_stock_defconfig` |  |
| a15 | `OP13r` | `6.1.75-android14-11-o-ge2f97ae7184b` | `a15/OP13r_stock_defconfig` | CPH2645_15.0.0.821(EX01) |
| a16 | `OP-ACE-2` | `5.10.236-android12-9-o-g74d132f4467a` | `a16/OP-ACE-2_stock_defconfig` |  |
| a16 | `OP-ACE-2-PRO` | `5.15.180-android13-8-o-01179-g408877dae2c9` | `a16/OP-ACE-2-PRO_stock_defconfig` |  |
| a16 | `OP-ACE-2V` | `5.10.236-android12-9-o-g7b827c1e7f33` | `a16/OP-ACE-2V_stock_defconfig` |  |
| a16 | `OP-ACE-3` | `5.15.180-android13-8-o-01179-g67e2990316c6` | `a16/OP-ACE-3_stock_defconfig` |  |
| a16 | `OP-ACE-3-PRO` | `6.1.141-android14-11-o-gffc54a6d2287` | `a16/OP-ACE-3-PRO_stock_defconfig` |  |
| a16 | `OP-ACE-3V` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-ACE-3V_stock_defconfig` |  |
| a16 | `OP-ACE-5` | `6.1.141-android14-11-o-g41d58e50fc53` | `a16/OP-ACE-5_stock_defconfig` |  |
| a16 | `OP-ACE-5-PRO` | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | `a16/OP-ACE-5-PRO_stock_defconfig` |  |
| a16 | `OP-ACE-5-RACE` | `6.1.115-android14-11-o-gae6c35f42659` | `a16/OP-ACE-5-RACE_stock_defconfig` |  |
| a16 | `OP-ACE-5-ULTRA` | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a16/OP-ACE-5-ULTRA_stock_defconfig` |  |
| a16 | `OP-ACE-6` | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | `a16/OP-ACE-6_stock_defconfig` |  |
| a16 | `OP-ACE-6-ULTRA` | `6.12.69-android16-6-g242e1a07f878-ab15865446-4k` | `a16/OP-ACE-6-ULTRA_stock_defconfig` | PMB110_17.0.0.101(CN01) |
| a16 | `OP-ACE-6T` | `6.12.38-android16-5-g844001fb8721-ab14552068-4k` | `a16/OP-ACE-6T_stock_defconfig` |  |
| a16 | `OP-N6` | `5.15.197-android13-8-o-g00d4e8e246c3` | `a16/OP-N6_stock_defconfig` |  |
| a16 | `OP-N6X` ⚠ | `5.15.197-android13-8-o-g00d4e8e246c3` | `a16/OP-N6X_stock_defconfig` | copy of a16/OP-N6 |
| a16 | `OP-NORD-3` | `5.10.246-android12-9-o-g1a9ce83500aa` | `a16/OP-NORD-3_stock_defconfig` | CPH2493_16.0.5.1301(EX01) |
| a16 | `OP-NORD-4` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-NORD-4_stock_defconfig` | CPH2663_16.0.5.1301(EX01) |
| a16 | `OP-NORD-4-CE` | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a16/OP-NORD-4-CE_stock_defconfig` | CPH2613_16.0.5.1301(EX01) |
| a16 | `OP-NORD-5` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-NORD-5_stock_defconfig` | CPH2709_16.0.5.1301(EX01) |
| a16 | `OP-NORD-6` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a16/OP-NORD-6_stock_defconfig` | CPH2795_16.0.5.1300(EX01) |
| a16 | `OP-NORD-CE-5` | `6.1.157-android14-11-o-g56556c5d6047` | `a16/OP-NORD-CE-5_stock_defconfig` |  |
| a16 | `OP-NORD-CE4-LITE` | `6.1.141-android14-11-o-g43b5e9582321` | `a16/OP-NORD-CE4-LITE_stock_defconfig` | CPH2621_16.0.5.1300(EX01) |
| a16 | `OP-NORD-CE6` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-NORD-CE6_stock_defconfig` | CPH2807_16.0.5.1301(EX01) |
| a16 | `OP-NORD-CE6-LITE` | `6.1.157-android14-11-o-gc2dad16af736` | `a16/OP-NORD-CE6-LITE_stock_defconfig` |  |
| a16 | `OP-OPEN` | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a16/OP-OPEN_stock_defconfig` | CPH2551_16.0.5.1301(EX01) |
| a16 | `OP-PAD-2-MT6991` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a16/OP-PAD-2-MT6991_stock_defconfig` | OPD2415_16.0.10.600(EX01) |
| a16 | `OP-PAD-2-PRO` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a16/OP-PAD-2-PRO_stock_defconfig` |  |
| a16 | `OP-PAD-2-SM8650` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-PAD-2-SM8650_stock_defconfig` | OPD2403_16.0.5.1301(EX01) |
| a16 | `OP-PAD-3-MT6897` | `6.1.128-android14-11-o-g415ded6ed906` | `a16/OP-PAD-3-MT6897_stock_defconfig` |  |
| a16 | `OP-PAD-3-PRO` | `6.12.58-android16-6-g7704a1ae279b-ab15213644-4k` | `a16/OP-PAD-3-PRO_stock_defconfig` |  |
| a16 | `OP-PAD-3-SM8750` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a16/OP-PAD-3-SM8750_stock_defconfig` | OPD2415_16.0.10.600(EX01) |
| a16 | `OP-PAD-4` | `6.12.58-android16-6-g7704a1ae279b-ab15213644-4k` | `a16/OP-PAD-4_stock_defconfig` | OPD2514_16.0.10.501(EX01) |
| a16 | `OP-PAD-GO-2` | `6.1.157-android14-11-o-gb72ba6fd16dd` | `a16/OP-PAD-GO-2_stock_defconfig` |  |
| a16 | `OP-PAD-LITE` | `6.12.58-android16-6-o-g96c5b8ea00fb-4k` | `a16/OP-PAD-LITE_stock_defconfig` | OPD2480_16.0.5.1301(EX01) |
| a16 | `OP-PAD-MT6983` | `5.10.149-android12-9-o-g55d4ce7d4557` | `a16/OP-PAD-MT6983_stock_defconfig` |  |
| a16 | `OP-PAD-PRO` | `6.1.141-android14-11-o-g5cdab3b518c1` | `a16/OP-PAD-PRO_stock_defconfig` |  |
| a16 | `OP-TURBO-6` | `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k` | `a16/OP-TURBO-6_stock_defconfig` |  |
| a16 | `OP-TURBO-6V` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-TURBO-6V_stock_defconfig` |  |
| a16 | `OP-TURBO-6X` ⚠ | `6.1.157-android14-11-o-gc2dad16af736` | `a16/OP-TURBO-6X_stock_defconfig` | copy of a16/OP-NORD-CE6-LITE |
| a16 | `OP10pro` | `5.10.236-android12-9-o-g9cbeeefc70f0` | `a16/OP10pro_stock_defconfig` | NE2213_16.0.3.530(EX01) |
| a16 | `OP11` | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a16/OP11_stock_defconfig` | CPH2449_16.0.5.1301(EX01) |
| a16 | `OP11r` | `5.10.246-android12-9-o-g931a7e2ba585` | `a16/OP11r_stock_defconfig` | CPH2487_16.0.5.1301(EX01) |
| a16 | `OP12` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP12_stock_defconfig` | CPH2581_16.0.10.601(EX01) |
| a16 | `OP12r` | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a16/OP12r_stock_defconfig` | CPH2609_16.0.5.1301(EX01) |
| a16 | `OP13` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a16/OP13_stock_defconfig` | CPH2653_16.0.10.600(EX01) |
| a16 | `OP13S` | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a16/OP13S_stock_defconfig` | CPH2723_17.0.0.101(EX01) |
| a16 | `OP13T` | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | `a16/OP13T_stock_defconfig` |  |
| a16 | `OP13r` | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP13r_stock_defconfig` | CPH2645_16.0.10.600(EX01) |
| a16 | `OP15` | `6.12.58-android16-6-g925a103d123c-ab15898589-4k` | `a16/OP15_stock_defconfig` | CPH2747_16.0.10.601(EX01) |
| a16 | `OP15T` | `6.12.38-android16-5-g844001fb8721-ab14552068-4k` | `a16/OP15T_stock_defconfig` |  |
| a16 | `OP15r` | `6.12.58-android16-6-g925a103d123c-ab15898589-4k` | `a16/OP15r_stock_defconfig` | CPH2769_16.0.10.600(EX01) |
