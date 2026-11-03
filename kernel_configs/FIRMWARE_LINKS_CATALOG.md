# Firmware from the Daniel Springer OTA catalog (roms.danielspringer.at)

That catalog (97 devices / 1262 releases) carries the CN-only and pad SKUs the
OTA-Pulse list doesn't. `source_url` is the same Oplus downloadCheck our pipeline resolves.

| repo model | device label | model code | rom | kernel in boot.img | link |
|---|---|---|---|---|---|
| OP-ACE-6-ULTRA | OP ACE 6 ULTRA | PMB110 | PMB110_17.0.0.101(CN01) | `6.12.69-android16-6-g242e1a07f878-ab15865446-4k` | [zip](https://gauss-compota-c-cn.allawnfs.com/remove-11e89ff0185b557a3b1e186e48ba6c73/g-10eab6008d5642cf42abd2aa41f847cb/component-ota/26/10/08/137492f3a34145fc8c576cfc33d2447c.zip?sign=350bd9f59d19b8e3c855b88fd24786b3&t=6ae966e3&AWSAccessKeyId=ayjy7KyLVHvDqDax6_KqJgtBeORTJARg9MSGiL66&Expires=1793682884&Signature=cbtC5pz5PZJOD%2FaRNs6Z0iHwZ%2FA%3D) |
| OP13S | OP 13S | CPH2723 | CPH2723_17.0.0.101(EX01) | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | [zip](https://gauss-compota-c-in.allawnofs.com/remove-505e350b0273cab0242032ec9a677cff/g-10eab6008d5642cf42abd2aa41f847cb/component-ota/26/10/21/21ea11321d5a4c83a67afbad7aa885cc.zip?sign=961e0c38489eb1487a9b99a57b6bb995&t=6ae96b9f&x-oss-signature=PyvBoK6rB5Ma%2F258Go8dHVoM46WkYCsF8xQTltw7POI%3D&x-oss-signature-version=OSS2&x-oss-expires=1793684135&x-oss-access-key-id=LTAI5t7LQqPWs3796pRv6Avx) |
| OP-PAD-LITE | OP PAD LITE | OPD2480 | OPD2480_16.0.5.1301(EX01) | `6.12.58-android16-6-o-g96c5b8ea00fb-4k` | [zip](https://gauss-compota-c-fr.allawnofs.com/remove-37544d379020034bccf405a8f5dfed10/g-10eab6008d5642cf42abd2aa41f847cb/component-ota/26/09/15/6dcea8f752e74a93ab6b940e674df409.zip?sign=f1fd08020ad0660b7b88bdad376a3aad&t=6ae96ba8&x-oss-signature=tvWe5XCKt8ADxq1nBMOAQW%2BoKs4tE4UK%2F3rsx02dWW8%3D&x-oss-signature-version=OSS2&x-oss-expires=1793684144&x-oss-access-key-id=LTAI5t7LQqPWs3796pRv6Avx) |
| OP-OPEN | OP OPEN | CPH2551 | CPH2551_16.0.5.1301(EX01) | `5.15.197-android13-8-o-01214-gbee5b6ef6244` | [zip](https://gauss-compota-c-fr.allawnofs.com/remove-35dc41491d9a2f523b2ae676bf2aec3d/g-10eab6008d5642cf42abd2aa41f847cb/component-ota/26/09/11/51b3489b8cb14460a65583f3c954436d.zip?sign=8cb7c85120d9715eb24e01ba9758799b&t=6ae96bb0&x-oss-signature=WDNmJ1qMYa96NMep%2Fz9RdwvL5QAaOoSTvsGoU6Cqfss%3D&x-oss-signature-version=OSS2&x-oss-expires=1793684152&x-oss-access-key-id=LTAI5t7LQqPWs3796pRv6Avx) |
| OP-PAD-2-MT6991 | OP PAD3 | OPD2415 | OPD2415_16.0.10.600(EX01) | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | [zip](https://gauss-compota-c-fr.allawnofs.com/remove-9d05eec7288937df74fec02420aeca4f/g-10eab6008d5642cf42abd2aa41f847cb/component-ota/26/09/14/eb0fd1bbe8f542fbad4d0bd741c8724f.zip?sign=3aba54825092eff08f56485b6f22fe04&t=6ae96bb8&x-oss-signature=O4od24%2FWN0M1jf6PyynnXnY1i0QBmUpzUypLfEzi92Q%3D&x-oss-signature-version=OSS2&x-oss-expires=1793684160&x-oss-access-key-id=LTAI5t7LQqPWs3796pRv6Avx) |
| OP-PAD-2-MT6991 | OP PAD2 PRO | OPD2413 | OPD2413_16.0.10.600(CN01) | `6.6.118-android15-8-gc4127a25dcf3-ab15863337-4k` | [zip](https://gauss-compota-c-cn.allawnfs.com/remove-3c135c61cd6dbcfdd055663598aaaaa1/g-10eab6008d5642cf42abd2aa41f847cb/component-ota/26/09/14/8f03d10e5a1b49f98ef3974f2e521c7b.zip?sign=f3f73052ddbaf54e3fe29585201bc12e&t=6ae9670f&AWSAccessKeyId=ayjy7KyLVHvDqDax6_KqJgtBeORTJARg9MSGiL66&Expires=1793682895&Signature=HLIjyL8qXKaUla0TX398h8S8vZo%3D) |

Catalog query used:
```
curl 'https://roms.danielspringer.at/api/ota.php?device=OP+ACE+6+ULTRA&latest=1'
```
