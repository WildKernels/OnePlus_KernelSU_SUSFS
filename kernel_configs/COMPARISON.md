# Stock config comparison — every device × every release

99 stock configs, extracted from compiled `boot.img`; 73 byte-distinct.
`CONFIG_UNUSED_KSYMS_WHITELIST` (absolute build-machine path) excluded from the comparison → **46 distinct configs**.

## Distinct configs (same = same group)

| group | count | line | kernel tag | members |
|---|---|---|---|---|
| G01 | 8 | 6.1 | `6.1.157-android14-11-o-g00d81d97d759` | `a16/OP-ACE-3V`, `a16/OP-NORD-4`, `a16/OP-NORD-5`, `a16/OP-NORD-CE6`, `a16/OP-PAD-2-SM8650`, `a16/OP-TURBO-6V`, `a16/OP12`, `a16/OP13r` |
| G02 | 7 | 6.1 | `6.1.118-android14-11-o-g1b63040d0a34` | `a15/OP-ACE-3-PRO`, `a15/OP-ACE-3V`, `a15/OP-ACE-5`, `a15/OP-NORD-4`, `a15/OP-PAD-2-SM8650`, `a15/OP-PAD-PRO`, `a15/OP12` |
| G03 | 7 | 6.6 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a15/OP13S`, `a16/OP-NORD-6`, `a16/OP-PAD-2-MT6991`, `a16/OP-PAD-2-PRO`, `a16/OP-PAD-3-SM8750`, `a16/OP13`, `a16/OP13S` |
| G04 | 5 | 5.15 | `5.15.167-android13-8-o-01144-gd83a4482a19d` | `a15/OP-ACE-2-PRO`, `a15/OP-ACE-3`, `a15/OP-NORD-4-CE`, `a15/OP11`, `a15/OP12r` |
| G05 | 5 | 6.6 | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a15/OP-ACE-5-PRO`, `a15/OP-ACE-5-ULTRA`, `a15/OP13-PJZ`, `a15/OP13T`, `a16/OP-ACE-5-ULTRA` |
| G06 | 5 | 5.15 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a15/OP-OPEN`, `a16/OP-NORD-4-CE`, `a16/OP-OPEN`, `a16/OP11`, `a16/OP12r` |
| G07 | 3 | 5.10 | `5.10.209-android12-9-o-g149ffe97838f` | `a14/OP-ACE-RACE`, `a14/OP10r`, `a15/OP10r` |
| G08 | 3 | 5.10 | `5.10.149-android12-9-o-g55d4ce7d4557` | `a14/OP-PAD-MT6983`, `a15/OP-PAD-MT6983`, `a16/OP-PAD-MT6983` |
| G09 | 3 | 5.10 | `5.10.226-android12-9-o-gbf90590695a1` | `a15/OP-ACE-2`, `a15/OP10pro`, `a15/OP11r` |
| G10 | 3 | 6.1 | `6.1.141-android14-11-o-gffc54a6d2287` | `a16/OP-ACE-3-PRO`, `a16/OP-ACE-5`, `a16/OP-PAD-PRO` |
| G11 | 3 | 6.6 | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | `a16/OP-ACE-5-PRO`, `a16/OP-ACE-6`, `a16/OP13T` |
| G12 | 2 | 5.10 | `5.10.209-android12-9-o-g8c421b8d3d52` | `a14/OP-ACE-2V`, `a14/OP-NORD-3` |
| G13 | 2 | 6.1 | `6.1.75-android14-11-o-g7cddc8f99e91` | `a14/OP-ACE-3-PRO`, `a14/OP-PAD-PRO` |
| G14 | 2 | 5.10 | `5.10.209-android12-9-o-g9dbebb7bc3d8` | `a14/OP10pro`, `a14/OP11r` |
| G15 | 2 | 6.1 | `6.1.115-android14-11-o-gae6c35f42659` | `a15/OP-ACE-5-RACE`, `a16/OP-ACE-5-RACE` |
| G16 | 2 | 6.6 | `6.6.57-android15-8-g7b1f455c7143-ab13591283-4k` | `a15/OP-PAD-2-PRO`, `a15/OP-PAD-3-SM8750` |
| G17 | 2 | 6.1 | `6.1.128-android14-11-o-g415ded6ed906` | `a15/OP-PAD-3-MT6897`, `a16/OP-PAD-3-MT6897` |
| G18 | 2 | 6.6 | `6.6.30-android15-8-g0261dbe3cf7e-ab12786384-4k` | `a15/OP13`, `a15/OP13-CPH` |
| G19 | 2 | 5.10 | `5.10.236-android12-9-o-g74d132f4467a` | `a16/OP-ACE-2`, `a16/OP10pro` |
| G20 | 2 | 5.15 | `5.15.180-android13-8-o-01179-g408877dae2c9` | `a16/OP-ACE-2-PRO`, `a16/OP-ACE-3` |
| G21 | 2 | 6.12 | `6.12.38-android16-5-g844001fb8721-ab14552068-4k` | `a16/OP-ACE-6T`, `a16/OP15T` |
| G22 | 2 | 6.12 | `6.12.58-android16-6-g7704a1ae279b-ab15213644-4k` | `a16/OP-PAD-3-PRO`, `a16/OP-PAD-4` |
| G23 | 2 | 6.12 | `6.12.58-android16-6-g925a103d123c-ab15898589-4k` | `a16/OP15`, `a16/OP15r` |
| G24 | 1 | 5.10 | `5.10.168-android12-9-o-g200cfbceef32` | `a14/OP-PAD-GO` |
| G25 | 1 | 5.15 | `5.15.123-android13-8-00766-gf04dea8b48fa` | `a14/OP11` |
| G26 | 1 | 6.1 | `6.1.57-android14-11-o-ga23ceff5d55d` | `a14/OP12` |
| G27 | 1 | 5.10 | `5.10.226-android12-9-o-g104a939c0e3e` | `a15/OP-ACE-2V` |
| G28 | 1 | 5.10 | `5.10.236-android12-9-o-g38e2c85bc7af` | `a15/OP-ACE-RACE` |
| G29 | 1 | 5.10 | `5.10.236-android12-9-o-g17fab92a617d` | `a15/OP-NORD-3` |
| G30 | 1 | 6.1 | `6.1.118-android14-11-o-g5223d7db527e` | `a15/OP-NORD-5` |
| G31 | 1 | 6.1 | `6.1.115-android14-11-o-gae6c35f42659` | `a15/OP-NORD-CE-5` |
| G32 | 1 | 6.1 | `6.1.118-android14-11-o-g36c82242b58f` | `a15/OP-NORD-CE4-LITE` |
| G33 | 1 | 5.10 | `5.10.236-android12-9-o-gfaf67edbfb7d` | `a15/OP-PAD-LITE` |
| G34 | 1 | 5.10 | `5.10.236-android12-9-o-g55571f3ffcfa` | `a15/OP10t` |
| G35 | 1 | 6.1 | `6.1.75-android14-11-o-ge2f97ae7184b` | `a15/OP13r` |
| G36 | 1 | 5.10 | `5.10.236-android12-9-o-g7b827c1e7f33` | `a16/OP-ACE-2V` |
| G37 | 1 | 6.12 | `6.12.69-android16-6-g242e1a07f878-ab15865446-4k` | `a16/OP-ACE-6-ULTRA` |
| G38 | 1 | 5.15 | `5.15.197-android13-8-o-g00d4e8e246c3` | `a16/OP-N6` |
| G39 | 1 | 5.10 | `5.10.246-android12-9-o-g1a9ce83500aa` | `a16/OP-NORD-3` |
| G40 | 1 | 6.1 | `6.1.157-android14-11-o-g56556c5d6047` | `a16/OP-NORD-CE-5` |
| G41 | 1 | 6.1 | `6.1.141-android14-11-o-g43b5e9582321` | `a16/OP-NORD-CE4-LITE` |
| G42 | 1 | 6.1 | `6.1.157-android14-11-o-gc2dad16af736` | `a16/OP-NORD-CE6-LITE` |
| G43 | 1 | 6.1 | `6.1.157-android14-11-o-gb72ba6fd16dd` | `a16/OP-PAD-GO-2` |
| G44 | 1 | 6.12 | `6.12.58-android16-6-o-g96c5b8ea00fb-4k` | `a16/OP-PAD-LITE` |
| G45 | 1 | 6.6 | `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k` | `a16/OP-TURBO-6` |
| G46 | 1 | 5.10 | `5.10.246-android12-9-o-g931a7e2ba585` | `a16/OP11r` |

## Per-file mapping

| file | group | kernel tag |
|---|---|---|
| `a14/OP-ACE-2V` | G12 | `5.10.209-android12-9-o-g8c421b8d3d52` |
| `a14/OP-ACE-3-PRO` | G13 | `6.1.75-android14-11-o-g7cddc8f99e91` |
| `a14/OP-ACE-RACE` | G07 | `5.10.209-android12-9-o-g149ffe97838f` |
| `a14/OP-NORD-3` | G12 | `5.10.209-android12-9-o-g2014171ac301` |
| `a14/OP-PAD-GO` | G24 | `5.10.168-android12-9-o-g200cfbceef32` |
| `a14/OP-PAD-MT6983` | G08 | `5.10.149-android12-9-o-g55d4ce7d4557` |
| `a14/OP-PAD-PRO` | G13 | `6.1.75-android14-11-o-gdbbbe9ebaaa8` |
| `a14/OP10pro` | G14 | `5.10.209-android12-9-o-g9dbebb7bc3d8` |
| `a14/OP10r` | G07 | `5.10.209-android12-9-o-g815b180d5b8a` |
| `a14/OP11` | G25 | `5.15.123-android13-8-00766-gf04dea8b48fa` |
| `a14/OP11r` | G14 | `5.10.209-android12-9-o-g8ba99bedf63b` |
| `a14/OP12` | G26 | `6.1.57-android14-11-o-ga23ceff5d55d` |
| `a15/OP-ACE-2` | G09 | `5.10.226-android12-9-o-gbf90590695a1` |
| `a15/OP-ACE-2-PRO` | G04 | `5.15.167-android13-8-o-01144-gd83a4482a19d` |
| `a15/OP-ACE-2V` | G27 | `5.10.226-android12-9-o-g104a939c0e3e` |
| `a15/OP-ACE-3` | G04 | `5.15.167-android13-8-o-01144-gdc8278c1c5f9` |
| `a15/OP-ACE-3-PRO` | G02 | `6.1.118-android14-11-o-g1b63040d0a34` |
| `a15/OP-ACE-3V` | G02 | `6.1.118-android14-11-o-ge56ebf48182b` |
| `a15/OP-ACE-5` | G02 | `6.1.118-android14-11-o-g778e4490e346` |
| `a15/OP-ACE-5-PRO` | G05 | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` |
| `a15/OP-ACE-5-RACE` | G15 | `6.1.115-android14-11-o-gae6c35f42659` |
| `a15/OP-ACE-5-ULTRA` | G05 | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` |
| `a15/OP-ACE-RACE` | G28 | `5.10.236-android12-9-o-g38e2c85bc7af` |
| `a15/OP-NORD-3` | G29 | `5.10.236-android12-9-o-g17fab92a617d` |
| `a15/OP-NORD-4` | G02 | `6.1.118-android14-11-o-g2f4ade3e433d` |
| `a15/OP-NORD-4-CE` | G04 | `5.15.167-android13-8-o-01144-g371cef69d4b6` |
| `a15/OP-NORD-5` | G30 | `6.1.118-android14-11-o-g5223d7db527e` |
| `a15/OP-NORD-CE-5` | G31 | `6.1.115-android14-11-o-gae6c35f42659` |
| `a15/OP-NORD-CE4-LITE` | G32 | `6.1.118-android14-11-o-g36c82242b58f` |
| `a15/OP-OPEN` | G06 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` |
| `a15/OP-PAD-2-PRO` | G16 | `6.6.57-android15-8-g7b1f455c7143-ab13591283-4k` |
| `a15/OP-PAD-2-SM8650` | G02 | `6.1.118-android14-11-o-g2b8edc801b38` |
| `a15/OP-PAD-3-MT6897` | G17 | `6.1.128-android14-11-o-g415ded6ed906` |
| `a15/OP-PAD-3-SM8750` | G16 | `6.6.57-android15-8-g7b1f455c7143-ab13591283-4k` |
| `a15/OP-PAD-LITE` | G33 | `5.10.236-android12-9-o-gfaf67edbfb7d` |
| `a15/OP-PAD-MT6983` | G08 | `5.10.149-android12-9-o-g55d4ce7d4557` |
| `a15/OP-PAD-PRO` | G02 | `6.1.118-android14-11-o-g2b8edc801b38` |
| `a15/OP10pro` | G09 | `5.10.226-android12-9-o-gb4f7990ee2d5` |
| `a15/OP10r` | G07 | `5.10.209-android12-9-o-g815b180d5b8a` |
| `a15/OP10t` | G34 | `5.10.236-android12-9-o-g55571f3ffcfa` |
| `a15/OP11` | G04 | `5.15.167-android13-8-o-01144-g65859ad20d1b` |
| `a15/OP11r` | G09 | `5.10.226-android12-9-o-gbf90590695a1` |
| `a15/OP12` | G02 | `6.1.118-android14-11-o-g818f2506c9e7` |
| `a15/OP12r` | G04 | `5.15.167-android13-8-o-01144-g55430422533e` |
| `a15/OP13` | G18 | `6.6.30-android15-8-g0261dbe3cf7e-ab12786384-4k` |
| `a15/OP13-CPH` | G18 | `6.6.30-android15-8-g0261dbe3cf7e-ab12786384-4k` |
| `a15/OP13-PJZ` | G05 | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` |
| `a15/OP13S` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a15/OP13T` | G05 | `6.6.66-android15-8-g174d20254551-abogki436492307-4k` |
| `a15/OP13r` | G35 | `6.1.75-android14-11-o-ge2f97ae7184b` |
| `a16/OP-ACE-2` | G19 | `5.10.236-android12-9-o-g74d132f4467a` |
| `a16/OP-ACE-2-PRO` | G20 | `5.15.180-android13-8-o-01179-g408877dae2c9` |
| `a16/OP-ACE-2V` | G36 | `5.10.236-android12-9-o-g7b827c1e7f33` |
| `a16/OP-ACE-3` | G20 | `5.15.180-android13-8-o-01179-g67e2990316c6` |
| `a16/OP-ACE-3-PRO` | G10 | `6.1.141-android14-11-o-gffc54a6d2287` |
| `a16/OP-ACE-3V` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP-ACE-5` | G10 | `6.1.141-android14-11-o-g41d58e50fc53` |
| `a16/OP-ACE-5-PRO` | G11 | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` |
| `a16/OP-ACE-5-RACE` | G15 | `6.1.115-android14-11-o-gae6c35f42659` |
| `a16/OP-ACE-5-ULTRA` | G05 | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` |
| `a16/OP-ACE-6` | G11 | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` |
| `a16/OP-ACE-6-ULTRA` | G37 | `6.12.69-android16-6-g242e1a07f878-ab15865446-4k` |
| `a16/OP-ACE-6T` | G21 | `6.12.38-android16-5-g844001fb8721-ab14552068-4k` |
| `a16/OP-N6` | G38 | `5.15.197-android13-8-o-g00d4e8e246c3` |
| `a16/OP-NORD-3` | G39 | `5.10.246-android12-9-o-g1a9ce83500aa` |
| `a16/OP-NORD-4` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP-NORD-4-CE` | G06 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` |
| `a16/OP-NORD-5` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP-NORD-6` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a16/OP-NORD-CE-5` | G40 | `6.1.157-android14-11-o-g56556c5d6047` |
| `a16/OP-NORD-CE4-LITE` | G41 | `6.1.141-android14-11-o-g43b5e9582321` |
| `a16/OP-NORD-CE6` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP-NORD-CE6-LITE` | G42 | `6.1.157-android14-11-o-gc2dad16af736` |
| `a16/OP-OPEN` | G06 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` |
| `a16/OP-PAD-2-MT6991` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a16/OP-PAD-2-PRO` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a16/OP-PAD-2-SM8650` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP-PAD-3-MT6897` | G17 | `6.1.128-android14-11-o-g415ded6ed906` |
| `a16/OP-PAD-3-PRO` | G22 | `6.12.58-android16-6-g7704a1ae279b-ab15213644-4k` |
| `a16/OP-PAD-3-SM8750` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a16/OP-PAD-4` | G22 | `6.12.58-android16-6-g7704a1ae279b-ab15213644-4k` |
| `a16/OP-PAD-GO-2` | G43 | `6.1.157-android14-11-o-gb72ba6fd16dd` |
| `a16/OP-PAD-LITE` | G44 | `6.12.58-android16-6-o-g96c5b8ea00fb-4k` |
| `a16/OP-PAD-MT6983` | G08 | `5.10.149-android12-9-o-g55d4ce7d4557` |
| `a16/OP-PAD-PRO` | G10 | `6.1.141-android14-11-o-g5cdab3b518c1` |
| `a16/OP-TURBO-6` | G45 | `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k` |
| `a16/OP-TURBO-6V` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP10pro` | G19 | `5.10.236-android12-9-o-g9cbeeefc70f0` |
| `a16/OP11` | G06 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` |
| `a16/OP11r` | G46 | `5.10.246-android12-9-o-g931a7e2ba585` |
| `a16/OP12` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP12r` | G06 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` |
| `a16/OP13` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a16/OP13S` | G03 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` |
| `a16/OP13T` | G11 | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` |
| `a16/OP13r` | G01 | `6.1.157-android14-11-o-g00d81d97d759` |
| `a16/OP15` | G23 | `6.12.58-android16-6-g925a103d123c-ab15898589-4k` |
| `a16/OP15T` | G21 | `6.12.38-android16-5-g844001fb8721-ab14552068-4k` |
| `a16/OP15r` | G23 | `6.12.58-android16-6-g925a103d123c-ab15898589-4k` |

## What separates them

**Close pairs (1–40 symbols apart)** — vendor feature toggles:

| symbol | pairs |
|---|---|
| `CONFIG_ARM_SDE_INTERFACE` | 165 |
| `CONFIG_MEMFD_ASHMEM_SHIM` | 163 |
| `CONFIG_QCOM_LMH` | 158 |
| `CONFIG_GKI_TASK_STRUCT_VENDOR_SIZE_MAX` | 124 |
| `CONFIG_HMBIRD_SCHED` | 120 |
| `CONFIG_ARCH_WANTS_DYNAMIC_TASK_STRUCT` | 120 |
| `CONFIG_GKI_DYNAMIC_TASK_STRUCT_SIZE` | 120 |
| `CONFIG_PAGE_BLOCK_ORDER` | 117 |
| `CONFIG_UNIX_SCM` | 117 |
| `CONFIG_UDMABUF` | 117 |
| `CONFIG_OPLUS_SCHED_TUNE` | 97 |
| `CONFIG_OPLUS_FEATURE_SKIP_CAMERA_UX` | 97 |

**Far pairs (>200 apart)** — platform/vendor stack (MTK vs Qualcomm devices):

| symbol | pairs |
|---|---|
| `CONFIG_MTK_VOW_BARGE_IN_SUPPORT` | 340 |
| `CONFIG_INTERCONNECT_MTK_MMQOS_MT6983` | 340 |
| `CONFIG_HSKEY_BLOCK` | 340 |
| `CONFIG_MTK_COMBO_CHIP_CONSYS_6879` | 340 |
| `CONFIG_MTK_SCP_AUDIO` | 340 |
| `CONFIG_HAPTIC_FEEDBACK` | 340 |
| `CONFIG_REGULATOR_MT6373` | 340 |
| `CONFIG_MTK_VOW_DUAL_MIC_SUPPORT` | 340 |
