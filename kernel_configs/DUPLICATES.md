# Stock config duplicates (byte-identical)

`kernel_configs/` holds 99 config files → 73 distinct configs; 15 groups are byte-identical, 26 files are redundant copies.

| copies | kernel inside boot.img | members |
|---|---|---|
| 7 | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | `a15/OP13S`, `a16/OP-NORD-6`, `a16/OP-PAD-2-MT6991`, `a16/OP-PAD-2-PRO`, `a16/OP-PAD-3-SM8750`, `a16/OP13S`, `a16/OP13` |
| 5 | `6.6.66-android15-8-g29d86c5fc9dd-abogki428889875-4k` | `a15/OP-ACE-5-PRO`, `a15/OP-ACE-5-ULTRA`, `a15/OP13-PJZ`, `a15/OP13T`, `a16/OP-ACE-5-ULTRA` |
| 3 | `5.10.149-android12-9-o-g55d4ce7d4557` | `a14/OP-PAD-MT6983`, `a15/OP-PAD-MT6983`, `a16/OP-PAD-MT6983` |
| 3 | `5.10.209-android12-9-o-g149ffe97838f` | `a14/OP-ACE-RACE`, `a14/OP10r`, `a15/OP10r` |
| 3 | `6.6.118-android15-8-g93e223c276e7-abogki500782043-4k` | `a16/OP-ACE-5-PRO`, `a16/OP-ACE-6`, `a16/OP13T` |
| 2 | `5.10.209-android12-9-o-g8c421b8d3d52` | `a14/OP-ACE-2V`, `a14/OP-NORD-3` |
| 2 | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | `a15/OP-OPEN`, `a16/OP-OPEN` |
| 2 | `6.1.115-android14-11-o-gae6c35f42659` | `a15/OP-ACE-5-RACE`, `a16/OP-ACE-5-RACE` |
| 2 | `6.1.118-android14-11-o-g2b8edc801b38` | `a15/OP-PAD-2-SM8650`, `a15/OP-PAD-PRO` |
| 2 | `6.1.128-android14-11-o-g415ded6ed906` | `a15/OP-PAD-3-MT6897`, `a16/OP-PAD-3-MT6897` |
| 2 | `6.12.38-android16-5-g844001fb8721-ab14552068-4k` | `a16/OP-ACE-6T`, `a16/OP15T` |
| 2 | `6.12.58-android16-6-g7704a1ae279b-ab15213644-4k` | `a16/OP-PAD-3-PRO`, `a16/OP-PAD-4` |
| 2 | `6.12.58-android16-6-g925a103d123c-ab15898589-4k` | `a16/OP15`, `a16/OP15r` |
| 2 | `6.6.30-android15-8-g0261dbe3cf7e-ab12786384-4k` | `a15/OP13-CPH`, `a15/OP13` |
| 2 | `6.6.57-android15-8-g7b1f455c7143-ab13591283-4k` | `a15/OP-PAD-2-PRO`, `a15/OP-PAD-3-SM8750` |

## Distinct configs that appear only once

- `a14/OP-PAD-GO` — `5.10.168-android12-9-o-g200cfbceef32`
- `a14/OP11r` — `5.10.209-android12-9-o-g8ba99bedf63b`
- `a14/OP10pro` — `5.10.209-android12-9-o-g9dbebb7bc3d8`
- `a15/OP-ACE-2V` — `5.10.226-android12-9-o-g104a939c0e3e`
- `a15/OP10pro` — `5.10.226-android12-9-o-gb4f7990ee2d5`
- `a15/OP-ACE-2` — `5.10.226-android12-9-o-gbf90590695a1`
- `a15/OP11r` — `5.10.226-android12-9-o-gbf90590695a1`
- `a15/OP-NORD-3` — `5.10.236-android12-9-o-g17fab92a617d`
- `a15/OP-ACE-RACE` — `5.10.236-android12-9-o-g38e2c85bc7af`
- `a15/OP10t` — `5.10.236-android12-9-o-g55571f3ffcfa`
- `a16/OP-ACE-2` — `5.10.236-android12-9-o-g74d132f4467a`
- `a16/OP-ACE-2V` — `5.10.236-android12-9-o-g7b827c1e7f33`
- `a16/OP10pro` — `5.10.236-android12-9-o-g9cbeeefc70f0`
- `a15/OP-PAD-LITE` — `5.10.236-android12-9-o-gfaf67edbfb7d`
- `a16/OP-NORD-3` — `5.10.246-android12-9-o-g1a9ce83500aa`
- `a16/OP11r` — `5.10.246-android12-9-o-g931a7e2ba585`
- `a14/OP11` — `5.15.123-android13-8-00766-gf04dea8b48fa`
- `a15/OP-NORD-4-CE` — `5.15.167-android13-8-o-01144-g371cef69d4b6`
- `a15/OP12r` — `5.15.167-android13-8-o-01144-g55430422533e`
- `a15/OP11` — `5.15.167-android13-8-o-01144-g65859ad20d1b`
- `a15/OP-ACE-2-PRO` — `5.15.167-android13-8-o-01144-gd83a4482a19d`
- `a15/OP-ACE-3` — `5.15.167-android13-8-o-01144-gdc8278c1c5f9`
- `a16/OP-ACE-2-PRO` — `5.15.180-android13-8-o-01179-g408877dae2c9`
- `a16/OP-ACE-3` — `5.15.180-android13-8-o-01179-g67e2990316c6`
- `a16/OP-NORD-4-CE` — `5.15.197-android13-8-o-01214-gbee5b6ef6244`
- `a16/OP11` — `5.15.197-android13-8-o-01214-gbee5b6ef6244`
- `a16/OP12r` — `5.15.197-android13-8-o-01214-gbee5b6ef6244`
- `a16/OP-N6` — `5.15.197-android13-8-o-g00d4e8e246c3`
- `a15/OP-NORD-CE-5` — `6.1.115-android14-11-o-gae6c35f42659`
- `a15/OP-ACE-3-PRO` — `6.1.118-android14-11-o-g1b63040d0a34`
- `a15/OP-NORD-4` — `6.1.118-android14-11-o-g2f4ade3e433d`
- `a15/OP-NORD-CE4-LITE` — `6.1.118-android14-11-o-g36c82242b58f`
- `a15/OP-NORD-5` — `6.1.118-android14-11-o-g5223d7db527e`
- `a15/OP-ACE-5` — `6.1.118-android14-11-o-g778e4490e346`
- `a15/OP12` — `6.1.118-android14-11-o-g818f2506c9e7`
- `a15/OP-ACE-3V` — `6.1.118-android14-11-o-ge56ebf48182b`
- `a16/OP-ACE-5` — `6.1.141-android14-11-o-g41d58e50fc53`
- `a16/OP-NORD-CE4-LITE` — `6.1.141-android14-11-o-g43b5e9582321`
- `a16/OP-PAD-PRO` — `6.1.141-android14-11-o-g5cdab3b518c1`
- `a16/OP-ACE-3-PRO` — `6.1.141-android14-11-o-gffc54a6d2287`
- `a16/OP-ACE-3V` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP-NORD-4` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP-NORD-5` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP-NORD-CE6` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP-PAD-2-SM8650` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP-TURBO-6V` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP12` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP13r` — `6.1.157-android14-11-o-g00d81d97d759`
- `a16/OP-NORD-CE-5` — `6.1.157-android14-11-o-g56556c5d6047`
- `a16/OP-PAD-GO-2` — `6.1.157-android14-11-o-gb72ba6fd16dd`
- `a16/OP-NORD-CE6-LITE` — `6.1.157-android14-11-o-gc2dad16af736`
- `a14/OP12` — `6.1.57-android14-11-o-ga23ceff5d55d`
- `a14/OP-ACE-3-PRO` — `6.1.75-android14-11-o-g7cddc8f99e91`
- `a14/OP-PAD-PRO` — `6.1.75-android14-11-o-gdbbbe9ebaaa8`
- `a15/OP13r` — `6.1.75-android14-11-o-ge2f97ae7184b`
- `a16/OP-PAD-LITE` — `6.12.58-android16-6-o-g96c5b8ea00fb-4k`
- `a16/OP-ACE-6-ULTRA` — `6.12.69-android16-6-g242e1a07f878-ab15865446-4k`
- `a16/OP-TURBO-6` — `6.6.118-android15-8-g9bc34d5b0c79-abogki537459655-4k`
