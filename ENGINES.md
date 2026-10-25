# Speech engines

What else Dysnow could speak with besides Kokoro, and what adding each one
takes. Researched in October 2026. Model support changes quickly, so the
points marked *to check* need checking before work starts.

## How an engine fits in

Every engine is a type behind `SpeechEngine` (`Dysnow/Speech/SpeechEngine.swift`):

- `languages` and `voices(for:)` fill the Language, Gender and Speaker pickers.
  The Model picker lists every engine with voices for the chosen language and
  gender.
- `isAvailable` is false until its model is downloaded. A downloader and a
  Settings section like Kokoro's (`KokoroInstaller`) go with each local engine.
- `synthesize(_:voice:language:speed:)` makes speech, off the main thread.
- An engine that can be told moods also adopts `MoodAwareEngine`. It is then
  given the `tts:mood` value as written, and Dysnow stops expressing the mood
  through pace and pauses (see [MARKUP.md](MARKUP.md)). Each engine translates
  the mood into its own controls, as shown below.
- `tts:speaker` names are looked up with `voice(named:preferring:)`, so they
  work with any engine's voices.

## The ways to run a model

| | How | For | Against |
|---|---|---|---|
| **A. sherpa-onnx** | The C library Dysnow already links for Kokoro | No new dependency; same process; same download-and-unpack code; works on Intel Macs too | Only the model families sherpa-onnx supports |
| **B. mlx-audio-swift** | Swift package, runs models on the GPU through Apple's MLX | Native Swift; many recent expressive models; MIT licence | Apple silicon only (M1 or later); a large new dependency; downloads from Hugging Face by itself, so its download location and progress need wiring into Dysnow's settings |
| **C. A Python helper process** | Dysnow starts a bundled Python with mlx-audio or PyTorch, and talks to it over a pipe | Every model as soon as it is released | Gigabytes of Python to ship, every library signed and notarised, slow to start: a last resort |
| **D. A cloud service** | HTTPS request to the provider's API | Best emotion control; many languages; nothing to download | Costs money per character; needs an API key (kept in the Keychain) and a network; the text leaves the Mac |

## Candidates

### Through sherpa-onnx (A): ready to use

The vendored release (1.13.8) already supports these model families: VITS
(Piper, MIMIC3), Matcha, Kokoro, Kitten, ZipVoice, Pocket and Supertonic.
Their models are in the same `tts-models` release on GitHub Kokoro comes
from. The release lists 646 files.

| Model | Languages | Mood control | Notes |
|---|---|---|---|
| **Piper** (`vits-piper-*`) | Over 30, **Hungarian included**: `hu_HU-anna-medium`, `hu_HU-berta-medium`, `hu_HU-imre-medium` | None: pace and pauses | Small (tens of MB per voice), fast, one voice per download. espeak-ng turns the text into sounds, as with Kokoro. Each voice has a model card with its licence: *to check* for the Hungarian ones |
| **MIMIC3** (`vits-mimic3-hu_HU-diana-majlinger_low`) | Hungarian, and others | None | Lower quality than Piper |
| **Kokoro 1.1** (`kokoro-multi-lang-v1_1`) | *To check*: what changed from 1.0 (more Chinese voices, as far as is known) | None | The same engine as now, a model swap |
| **ZipVoice** (`zipvoice-*-zh-en-emilia`) | Chinese, English | **By example**: copies the voice and the manner of a short recording given with each request | The engine interface already has `reference_audio` and `reference_text` fields. A short clip per mood ("excited", "sad") would give moods without the model being told them. Also cloning a voice from a sample |
| **Pocket TTS** (`pocket-tts-2026-01-26`) | English | By example, like ZipVoice | Small and fast; *to check*: does a reference clip carry the mood well? |
| **Supertonic** (`supertonic-3-tts-2026-05-11`) | *To check* | A style file per voice | Very fast according to its authors |
| **Kitten** | English | None | Tiny: for low-end Macs |

**Work involved:** for Piper, small. It is a VITS configuration instead of a
Kokoro one in the same `SherpaOnnxOfflineTtsConfig`, a catalogue of the
voices, and the existing installer, pointed at one archive per voice. For
ZipVoice or Pocket with moods by example, medium: the same, plus a set of
reference clips per mood, and a mood-aware engine that picks the clip.

### Through mlx-audio-swift (B): expressive, Apple silicon only

The package (`https://github.com/Blaizzy/mlx-audio-swift`, product
`MLXAudioTTS`, macOS 14+) lists Qwen3-TTS, OmniVoice, Fish Audio S2 Pro,
Orpheus, IndexTTS, Spark-TTS, Dia, Pocket TTS, Soprano, Marvis and others.
Models are loaded by their Hugging Face name with `fromPretrained`, and
`generate(text:parameters:)` returns the samples. The package's README does
not say which models' emotion controls it exposes: *to check*, model by model.

| Model | Languages | Mood control | How `tts:mood` would map |
|---|---|---|---|
| **Qwen3-TTS** (0.6B / 1.7B, "CustomVoice") | 10: Chinese, English, Japanese, Korean, German, French, Russian, Portuguese, Spanish, Italian. **No Hungarian** | A written instruction: timbre, emotion, delivery | `excited` becomes "Speak in an excited tone." Free text could also be passed through as is. The most promising instruction-driven model; *to check*: does the Swift port take the instruction? |
| **Orpheus** (3B) | English, mainly | Tags in the text: `<laugh>`, `<sigh>`, `<gasp>`, `<groan>`, … (only in the fine-tuned model) | Those are sounds, not moods. They would need a markup of their own (`tts:sound`) |
| **IndexTTS 2** | Chinese, English | Emotion kept apart from the speaker: from a recording, a written label, or a vector | `sad` passed as the label. Its licence needs reading |
| **Dia** (1.6B) | English | Dialogue with `[S1]`/`[S2]` speakers and sounds like `(laughs)` | Fits conversations: `tts:speaker` could map to its `[S1]`/`[S2]` |
| **Chatterbox** | 23 languages, **no Hungarian** | One "exaggeration" number (0.5 normal, 0.7 and up for lively) | `excited` gives 0.8, `calm` 0.3. Reported to also exist as an ONNX export (`onnx-community/chatterbox-ONNX`), but its token-by-token generation would have to be written for our ONNX Runtime by hand |

**Work involved:** medium to large. The package and MLX go into the project,
then one engine type per model. The downloads have to be steered into
Dysnow's model folder, with progress shown. These are hundreds of MB to
several GB each, and slower than Kokoro. Some need several GB of memory.

### Cloud services (D)

| Service | Mood control | Hungarian |
|---|---|---|
| **OpenAI** speech (`gpt-4o-mini-tts`) | `instructions`: free text for tone, emotion, pace, whispering | The voices are "optimized for English": *to check* |
| **ElevenLabs** v3 | Tags in the text: `[excited]`, `[whispers]`, `[sighs]`, `[laughs]`, … | *To check*; its multilingual models are known to cover many languages |
| **Google Gemini TTS** | A written style prompt: style, accent, pace, tone, emotion | *To check*: the language list is on its own documentation page |
| **Azure Speech** | SSML speaking styles (`cheerful`, `sad`, …) for some voices | Hungarian voices exist; *to check*: whether they have styles |

The mapping is direct: `tts:mood` becomes the instruction, the tag or the
style, and `tts:speaker` the service's voice name. **Work involved:**
small per service: an HTTP request, the API key in the Keychain, a voice
list. Saving long texts then costs money, which the save queue should show
before it starts.

## Suggested order

1. **Piper's Hungarian voices** through sherpa-onnx. *Done*:
   `Dysnow/Speech/PiperEngine.swift`. More Piper voices are a line each in
   `PiperVoice.all`, with the archive's name and SHA-256 from the release.
2. **A trial of mlx-audio-swift with Qwen3-TTS**, in a branch. Measure the
   speed and memory on a real Mac, and check that instructions reach the
   model. If it holds up, it is the first `MoodAwareEngine`, and the
   others in the package follow cheaply.
3. ~~One cloud engine~~: decided against, so emotional Hungarian waits for
   a local model that has it.
4. **Moods by example** with ZipVoice or Pocket TTS, as an experiment.

## Sources

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), and its
  [tts-models release](https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models)
- [sherpa-onnx Piper models](https://github.com/k2-fsa/sherpa/blob/master/docs/source/onnx/tts/piper.rst)
- [Pocket TTS C API example](https://github.com/k2-fsa/sherpa-onnx/blob/master/c-api-examples/pocket-tts-en-c-api.c)
- [mlx-audio-swift](https://github.com/Blaizzy/mlx-audio-swift), [mlx-audio](https://github.com/Blaizzy/mlx-audio)
- [Qwen3-TTS](https://www.mintlify.com/QwenLM/Qwen3-TTS/introduction),
  [Qwen3-TTS 0.6B CustomVoice](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice),
  [Qwen3-TTS with MLX-Audio on macOS](https://mybyways.com/blog/qwen3-tts-with-mlx-audio-on-macos)
- [Chatterbox ONNX](https://huggingface.co/onnx-community/chatterbox-ONNX),
  [Chatterbox multilingual](https://github.com/travisvn/chatterbox-multilingual)
- [TTS model comparison chart](https://github.com/mirfahimanwar/TTS-Model-Comparison-Chart/),
  [CosyVoice / FunAudioLLM paper](https://arxiv.org/pdf/2407.04051)
- [ElevenLabs v3 audio tags](https://elevenlabs.io/blog/v3-audiotags),
  [OpenAI text to speech](https://developers.openai.com/api/docs/guides/text-to-speech),
  [Gemini TTS](https://docs.cloud.google.com/text-to-speech/docs/gemini-tts),
  [Gemini API speech generation](https://ai.google.dev/gemini-api/docs/speech-generation)
