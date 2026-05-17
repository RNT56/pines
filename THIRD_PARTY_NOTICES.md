# Third-Party Notices

This file documents third-party software dependencies used by Pines. The Pines repository license does not relicense third-party software. Each dependency remains available under its own license.

This inventory was checked against `project.yml`, `Package.swift`, dependency manifests, and the committed package lockfile on May 17, 2026. The iOS app package graph was last resolved by `xcodebuild -resolvePackageDependencies` on May 16, 2026. The Swift package lockfile covers package/test dependencies; the iOS app MLX fork dependencies are exact revision pins in `project.yml`.

## Direct Swift Package Dependencies

| Package | Source | Version or revision | Products used | License | Notice |
| --- | --- | --- | --- | --- | --- |
| MLXSwift | <https://github.com/RNT56/mlx-swift> | `2577c8856ddfb05cad0da4eda7b502cbb5d99a3f` | `MLX`, `MLXNN` | MIT | Copyright (c) 2023 ml-explore |
| MLXSwiftLM | <https://github.com/RNT56/mlx-swift-lm> | `8861b2d9746128f3461b71deee5bf94ec3817a78` | `MLXLLM`, `MLXVLM`, `MLXEmbedders`, `MLXLMCommon` | MIT | Copyright (c) 2024 ml-explore |
| SwiftHuggingFace | <https://github.com/huggingface/swift-huggingface.git> | `0.9.0`, with `Xet` trait enabled through `PinesHubXetSupport` | `HuggingFace` | Apache-2.0 | See Apache-2.0 text below. |
| SwiftTransformers | <https://github.com/huggingface/swift-transformers> | `1.3.2` | `Tokenizers` | Apache-2.0 | See Apache-2.0 text below. |
| GRDB | <https://github.com/groue/GRDB.swift.git> | `7.10.0` | `GRDB` | MIT | Copyright (C) 2015-2025 Gwendal Roué |
| Swift Markdown | <https://github.com/swiftlang/swift-markdown.git> | `0.8.0` | `Markdown` | Apache-2.0 | Includes Swift Markdown `NOTICE.txt` below. |
| HighlightSwift | <https://github.com/appstefan/highlightswift.git> | `1.1.0` | `HighlightSwift` | MIT | Copyright (c) 2023 Stefan Britton |

## Manifest-Visible Transitive Dependencies

These packages are declared by the direct dependencies above. Some are build, documentation, test, benchmark, or feature-gated dependencies rather than runtime code linked into the app by default.

| Package | Source | Declared by | Version or revision | Scope | License | Notice |
| --- | --- | --- | --- | --- | --- | --- |
| EventSource | <https://github.com/mattt/EventSource.git> | SwiftHuggingFace | `1.4.1` | Runtime dependency of `HuggingFace` | Apache-2.0 | See Apache-2.0 text below. |
| Swift Crypto | <https://github.com/apple/swift-crypto.git> | SwiftHuggingFace, SwiftTransformers | `4.5.0` | Runtime dependency | Apache-2.0 | Includes Swift Crypto `NOTICE.txt` below. |
| swift-xet | <https://github.com/huggingface/swift-xet.git> | SwiftHuggingFace `Xet` trait | `0.2.3` | Runtime dependency of Xet-enabled `HuggingFace` downloads | Apache-2.0 on the repository default branch; see known gap below. | The `0.2.x` tags did not include a license file when this inventory was prepared. |
| AsyncHTTPClient | <https://github.com/swift-server/async-http-client.git> | swift-xet | `1.33.1` | Runtime dependency of `swift-xet` | Apache-2.0 | See Apache-2.0 text below. |
| SwiftNIO | <https://github.com/apple/swift-nio.git> | swift-xet and AsyncHTTPClient | `2.99.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| SwiftNIO Extras | <https://github.com/apple/swift-nio-extras.git> | AsyncHTTPClient | `1.34.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| SwiftNIO HTTP/2 | <https://github.com/apple/swift-nio-http2.git> | AsyncHTTPClient | `1.43.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| SwiftNIO SSL | <https://github.com/apple/swift-nio-ssl.git> | AsyncHTTPClient | `2.37.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| SwiftNIO Transport Services | <https://github.com/apple/swift-nio-transport-services.git> | AsyncHTTPClient | `1.28.0` | Runtime dependency of Xet transport networking on Apple platforms | Apache-2.0 | See Apache-2.0 text below. |
| Swift Log | <https://github.com/apple/swift-log.git> | AsyncHTTPClient, SwiftNIO packages | `1.12.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift Distributed Tracing | <https://github.com/apple/swift-distributed-tracing.git> | AsyncHTTPClient, SwiftNIO packages | `1.4.1` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift Service Context | <https://github.com/apple/swift-service-context.git> | Swift Distributed Tracing | `1.3.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift Service Lifecycle | <https://github.com/swift-server/swift-service-lifecycle> | AsyncHTTPClient | `2.11.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift HTTP Types | <https://github.com/apple/swift-http-types.git> | AsyncHTTPClient | `1.5.1` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift HTTP Structured Headers | <https://github.com/apple/swift-http-structured-headers.git> | AsyncHTTPClient | `1.7.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift Certificates | <https://github.com/apple/swift-certificates.git> | SwiftNIO SSL | `1.19.1` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift ASN.1 | <https://github.com/apple/swift-asn1.git> | Swift Certificates | `1.7.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift Configuration | <https://github.com/apple/swift-configuration.git> | AsyncHTTPClient | `1.2.0` | Runtime dependency of Xet transport networking | Apache-2.0 | See Apache-2.0 text below. |
| Swift Algorithms | <https://github.com/apple/swift-algorithms.git> | Swift Collections and SwiftNIO packages | `1.2.1` | Runtime dependency | Apache-2.0 | See Apache-2.0 text below. |
| Swift Async Algorithms | <https://github.com/apple/swift-async-algorithms.git> | SwiftNIO packages | `1.1.3` | Runtime dependency | Apache-2.0 | See Apache-2.0 text below. |
| Swift Atomics | <https://github.com/apple/swift-atomics.git> | Swift Collections and SwiftNIO packages | `1.3.0` | Runtime dependency | Apache-2.0 | See Apache-2.0 text below. |
| Swift System | <https://github.com/apple/swift-system.git> | SwiftNIO packages | `1.6.4` | Runtime dependency | Apache-2.0 | See Apache-2.0 text below. |
| Swift Jinja | <https://github.com/huggingface/swift-jinja.git> | SwiftTransformers | `2.3.5` | Runtime dependency of `Tokenizers` | Apache-2.0 | See Apache-2.0 text below. |
| Swift Collections | <https://github.com/apple/swift-collections.git> | SwiftTransformers, Swift Jinja | `1.5.0` | Runtime dependency | Apache-2.0 | See Apache-2.0 text below. |
| Swift Numerics | <https://github.com/apple/swift-numerics> | MLXSwift | `1.1.1` | Runtime dependency | Apache-2.0 | See Apache-2.0 text below. |
| Swift Syntax | <https://github.com/swiftlang/swift-syntax.git> | MLXSwiftLM | `603.0.1` | Build-time and macro/parser support | Apache-2.0 | See Apache-2.0 text below. |
| Swift CMark | <https://github.com/swiftlang/swift-cmark.git> | Swift Markdown | `0.8.0` | Runtime parser dependency | BSD-2-Clause | Derived from cmark-gfm; see BSD license text below. |
| Swift DocC Plugin | <https://github.com/apple/swift-docc-plugin> | MLXSwift, MLXSwiftLM | from `1.3.0` | Documentation tooling | Apache-2.0 | See Apache-2.0 text below. |
| Swift DocC SymbolKit | <https://github.com/apple/swift-docc-symbolkit> | Swift DocC Plugin | from `1.0.0` | Documentation tooling | Apache-2.0 | See Apache-2.0 text below. |
| yyjson | <https://github.com/ibireme/yyjson.git> | SwiftTransformers | exact `0.12.0` | Test and benchmark targets in SwiftTransformers | MIT | Copyright (c) 2020 YaoYuan <ibireme@gmail.com> |
| Highlight.js | <https://github.com/highlightjs/highlight.js> | HighlightSwift | bundled `11.9.0` | Runtime syntax highlighting resource | BSD-3-Clause | Copyright (c) 2006, Ivan Sagalaev |

## Known License Metadata Gap

Pines enables SwiftHuggingFace's `Xet` trait through the `PinesHubXetSupport` Swift package product. The `swift-xet` `0.2.x` tags did not include a license file when this inventory was prepared, although the repository's default branch later includes an Apache-2.0 license file. Treat this as an accepted upstream metadata gap until a tagged `swift-xet` release includes the license file or Pines pins a revision that contains it.

## MIT-Licensed Dependency Notices

The following MIT-licensed dependency notices are preserved:

- MLXSwift: Copyright (c) 2023 ml-explore
- MLXSwiftLM: Copyright (c) 2024 ml-explore
- GRDB: Copyright (C) 2015-2025 Gwendal Roué
- HighlightSwift: Copyright (c) 2023 Stefan Britton
- yyjson: Copyright (c) 2020 YaoYuan <ibireme@gmail.com>

### MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## BSD-Licensed Dependency Notices

- Swift CMark / cmark-gfm: BSD-2-Clause.
- Highlight.js: BSD-3-Clause. Copyright (c) 2006, Ivan Sagalaev.

### BSD-2-Clause License

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES.

### BSD-3-Clause License

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES.

## Swift Markdown Notice

The Swift Markdown Project
==========================

Please visit the Swift Markdown web site for more information:

* <https://github.com/swiftlang/swift-markdown>

Copyright (c) 2021 Apple Inc. and the Swift project authors

The Swift Project licenses this file to you under the Apache License, version 2.0. This product contains a derivation of the cmark-gfm project, available at <https://github.com/swiftlang/swift-cmark>.

## Swift Crypto Notice

The SwiftCrypto Project
=======================

Please visit the SwiftCrypto web site for more information:

* <https://github.com/apple/swift-crypto>

Copyright 2019 The SwiftCrypto Project

The SwiftCrypto Project licenses this file to you under the Apache License, version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at:

<https://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

Also, please refer to each `LICENSE.<component>.txt` file, which is located in the `license` directory of the distribution file, for the license terms of the components that this product depends on.

This product contains test vectors from Google's wycheproof project.

* LICENSE (Apache License 2.0): <https://github.com/google/wycheproof/blob/master/LICENSE>
* HOMEPAGE: <https://github.com/google/wycheproof>

This product contains a derivation of various scripts from SwiftNIO.

* LICENSE (Apache License 2.0): <https://www.apache.org/licenses/LICENSE-2.0>
* HOMEPAGE: <https://github.com/apple/swift-nio>

## Apache-2.0 License Text

Apache License
Version 2.0, January 2004
http://www.apache.org/licenses/

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

1. Definitions.

"License" shall mean the terms and conditions for use, reproduction, and distribution as defined by Sections 1 through 9 of this document.

"Licensor" shall mean the copyright owner or entity authorized by the copyright owner that is granting the License.

"Legal Entity" shall mean the union of the acting entity and all other entities that control, are controlled by, or are under common control with that entity. For the purposes of this definition, "control" means (i) the power, direct or indirect, to cause the direction or management of such entity, whether by contract or otherwise, or (ii) ownership of fifty percent (50%) or more of the outstanding shares, or (iii) beneficial ownership of such entity.

"You" (or "Your") shall mean an individual or Legal Entity exercising permissions granted by this License.

"Source" form shall mean the preferred form for making modifications, including but not limited to software source code, documentation source, and configuration files.

"Object" form shall mean any form resulting from mechanical transformation or translation of a Source form, including but not limited to compiled object code, generated documentation, and conversions to other media types.

"Work" shall mean the work of authorship, whether in Source or Object form, made available under the License, as indicated by a copyright notice that is included in or attached to the work (an example is provided in the Appendix below).

"Derivative Works" shall mean any work, whether in Source or Object form, that is based on (or derived from) the Work and for which the editorial revisions, annotations, elaborations, or other modifications represent, as a whole, an original work of authorship. For the purposes of this License, Derivative Works shall not include works that remain separable from, or merely link (or bind by name) to the interfaces of, the Work and Derivative Works thereof.

"Contribution" shall mean any work of authorship, including the original version of the Work and any modifications or additions to that Work or Derivative Works thereof, that is intentionally submitted to Licensor for inclusion in the Work by the copyright owner or by an individual or Legal Entity authorized to submit on behalf of the copyright owner. For the purposes of this definition, "submitted" means any form of electronic, verbal, or written communication sent to the Licensor or its representatives, including but not limited to communication on electronic mailing lists, source code control systems, and issue tracking systems that are managed by, or on behalf of, the Licensor for the purpose of discussing and improving the Work, but excluding communication that is conspicuously marked or otherwise designated in writing by the copyright owner as "Not a Contribution."

"Contributor" shall mean Licensor and any individual or Legal Entity on behalf of whom a Contribution has been received by Licensor and subsequently incorporated within the Work.

2. Grant of Copyright License.

Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable copyright license to reproduce, prepare Derivative Works of, publicly display, publicly perform, sublicense, and distribute the Work and such Derivative Works in Source or Object form.

3. Grant of Patent License.

Subject to the terms and conditions of this License, each Contributor hereby grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, irrevocable patent license to make, have made, use, offer to sell, sell, import, and otherwise transfer the Work, where such license applies only to those patent claims licensable by such Contributor that are necessarily infringed by their Contribution(s) alone or by combination of their Contribution(s) with the Work to which such Contribution(s) was submitted. If You institute patent litigation against any entity (including a cross-claim or counterclaim in a lawsuit) alleging that the Work or a Contribution incorporated within the Work constitutes direct or contributory patent infringement, then any patent licenses granted to You under this License for that Work shall terminate as of the date such litigation is filed.

4. Redistribution.

You may reproduce and distribute copies of the Work or Derivative Works thereof in any medium, with or without modifications, and in Source or Object form, provided that You meet the following conditions:

(a) You must give any other recipients of the Work or Derivative Works a copy of this License; and

(b) You must cause any modified files to carry prominent notices stating that You changed the files; and

(c) You must retain, in the Source form of any Derivative Works that You distribute, all copyright, patent, trademark, and attribution notices from the Source form of the Work, excluding those notices that do not pertain to any part of the Derivative Works; and

(d) If the Work includes a "NOTICE" text file as part of its distribution, then any Derivative Works that You distribute must include a readable copy of the attribution notices contained within such NOTICE file, excluding those notices that do not pertain to any part of the Derivative Works, in at least one of the following places: within a NOTICE text file distributed as part of the Derivative Works; within the Source form or documentation, if provided along with the Derivative Works; or, within a display generated by the Derivative Works, if and wherever such third-party notices normally appear. The contents of the NOTICE file are for informational purposes only and do not modify the License. You may add Your own attribution notices within Derivative Works that You distribute, alongside or as an addendum to the NOTICE text from the Work, provided that such additional attribution notices cannot be construed as modifying the License.

You may add Your own copyright statement to Your modifications and may provide additional or different license terms and conditions for use, reproduction, or distribution of Your modifications, or for any such Derivative Works as a whole, provided Your use, reproduction, and distribution of the Work otherwise complies with the conditions stated in this License.

5. Submission of Contributions.

Unless You explicitly state otherwise, any Contribution intentionally submitted for inclusion in the Work by You to the Licensor shall be under the terms and conditions of this License, without any additional terms or conditions. Notwithstanding the above, nothing herein shall supersede or modify the terms of any separate license agreement you may have executed with Licensor regarding such Contributions.

6. Trademarks.

This License does not grant permission to use the trade names, trademarks, service marks, or product names of the Licensor, except as required for reasonable and customary use in describing the origin of the Work and reproducing the content of the NOTICE file.

7. Disclaimer of Warranty.

Unless required by applicable law or agreed to in writing, Licensor provides the Work (and each Contributor provides its Contributions) on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied, including, without limitation, any warranties or conditions of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A PARTICULAR PURPOSE. You are solely responsible for determining the appropriateness of using or redistributing the Work and assume any risks associated with Your exercise of permissions under this License.

8. Limitation of Liability.

In no event and under no legal theory, whether in tort (including negligence), contract, or otherwise, unless required by applicable law (such as deliberate and grossly negligent acts) or agreed to in writing, shall any Contributor be liable to You for damages, including any direct, indirect, special, incidental, or consequential damages of any character arising as a result of this License or out of the use or inability to use the Work (including but not limited to damages for loss of goodwill, work stoppage, computer failure or malfunction, or any and all other commercial damages or losses), even if such Contributor has been advised of the possibility of such damages.

9. Accepting Warranty or Additional Liability.

While redistributing the Work or Derivative Works thereof, You may choose to offer, and charge a fee for, acceptance of support, warranty, indemnity, or other liability obligations and/or rights consistent with this License. However, in accepting such obligations, You may act only on Your own behalf and on Your sole responsibility, not on behalf of any other Contributor, and only if You agree to indemnify, defend, and hold each Contributor harmless for any liability incurred by, or claims asserted against, such Contributor by reason of your accepting any such warranty or additional liability.

END OF TERMS AND CONDITIONS

APPENDIX: How to apply the Apache License to your work.

To apply the Apache License to your work, attach the following boilerplate notice, with the fields enclosed by brackets "[]" replaced with your own identifying information. (Don't include the brackets!)  The text should be enclosed in the appropriate comment syntax for the file format. We also recommend that a file or class name and description of purpose be included on the same "printed page" as the copyright notice for easier identification within third-party archives.

Copyright [yyyy] [name of copyright owner]

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
