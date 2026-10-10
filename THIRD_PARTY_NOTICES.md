# Third-party notices

Hark itself is released under the MIT licence (see `LICENSE`). It uses the two things below.

## FluidAudio

- What it is: a Swift package that runs speech models on a Mac.
- Version used: 0.17.7, pinned in `Package.swift`.
- Source: https://github.com/FluidInference/FluidAudio
- Licence: Apache License, Version 2.0. The full text is in the `LICENSE` file of the FluidAudio
  source, which SwiftPM downloads to `.build/checkouts/FluidAudio/LICENSE` when you build.
- Where Hark uses it: `Sources/HarkMac/Speech/ParakeetTranscriber.swift` loads and runs the speech
  model through FluidAudio.

FluidAudio keeps notices for code and data it includes in its `ThirdPartyLicenses` folder. The files
there are listed below with what each one says it covers. They were read from the checkout, and
their text is in that folder, not repeated here.

| File | What it covers, as the file states it |
|---|---|
| `fastcluster-LICENSE.md` | The fastcluster library, copyright Daniel Muellner and Google Inc. The text is a BSD-style licence (redistribution with or without modification under conditions). |
| `JapaneseG2P-LICENSE.md` | A Japanese text frontend adapted from Misaki (Apache-2.0), itself adapted from cutlet (MIT), plus other word lists and data it names. |
| `KokoroAneSpanishFrenchG2P-LICENSE.md` | Spanish and French text frontends, with data from sources it names, including ipa-dict (MIT) and CharsiuG2P (MIT). |
| `NemoTextProcessing-LICENSE.md` | The `text-processing-rs` library, "Apache License, Version 2.0", built from NVIDIA NeMo Text Processing, with the permissive (Apache-2.0 or MIT) works it links listed in the file. |
| `vbx-LICENSE.md` | An Apache License, Version 2.0 text for the VBx diarization work. |
| `KokoroANE-v3/` (`NOTICE`, `conversion-LICENSE`, `mattmireles-LICENSE`) | Text-to-speech conversion work based on mattmireles/kokoro-coreml (Apache License 2.0). |

Most of these belong to FluidAudio features that Hark does not call (for example text to speech and
speaker separation). Hark only transcribes speech. If you redistribute a build of Hark, check that
folder against what your build links, and keep the notices that apply.

## Parakeet speech model weights

- Model: Parakeet TDT v2, English, about 0.6 billion parameters. The code asks for it as
  `AsrModels.downloadAndLoad(version: .v2)`. FluidAudio fetches a Core ML conversion published as
  `FluidInference/parakeet-tdt-0.6b-v2-coreml` on Hugging Face.
- Made by: NVIDIA.
- Licence: CC-BY-4.0 (Creative Commons Attribution 4.0 International). This is the licence recorded
  in the project's decision 0009. No licence file for the weights is included in this repository or
  in the FluidAudio checkout, so confirm the terms on the model page before you redistribute the
  weights. Attribution is required: this notice is that credit.
- Where Hark uses it: `Sources/HarkMac/Speech/ParakeetTranscriber.swift`. The weights are not part
  of this repository. Hark downloads them on first run, about 451 MB, and runs them on the Mac.
