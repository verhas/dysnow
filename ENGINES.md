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
| **Piper** (`vits-piper-*`) | Over 30, **Hungarian included**: `hu_HU-anna-medium`, `hu_HU-berta-medium`, `hu_HU-imre-medium` | None: pace and pauses | Small (26 to 130 MB a download), fast, one voice or a few per download. espeak-ng turns the text into sounds, as with Kokoro. *Done*: all 185 of sherpa-onnx's Piper downloads are offered, by language, from `Dysnow/Speech/PiperCatalog.swift`, written by `tools/piper_catalog.py`; each voice's licence comes from its model card |
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
2. **Qwen3-TTS through mlx-audio-swift**. *Done*:
   `Dysnow/Speech/Qwen3Engine.swift`, the first `MoodAwareEngine`. Details
   below. Other models in the package follow the same pattern.
3. ~~One cloud engine~~: decided against, so emotional Hungarian waits for
   a local model that has it.
4. **ZipVoice and Pocket TTS**, speaking in the user's own voices, with
   moods by example. *Done*: `Dysnow/Speech/CloningEngine.swift`. Details
   below.

## Qwen3-TTS as built

- **Package:** `mlx-audio-swift` pinned to exactly 0.1.6, with `mlx-swift`
  from 0.32.3, both through Swift Package Manager in the Xcode project. The
  app links `MLXAudioTTS`, `MLXAudioCore` and `MLX`.
- **Models:** the CustomVoice models from `mlx-community`, 8-bit: 0.6B
  (1.9 GB, the default) and 1.7B (2.9 GB), chosen in Settings. Apache 2.0.
  Each is pinned to a commit.
- **Download:** Dysnow fetches the files itself (`HuggingFaceDownloader`),
  into `~/.dysnow/voices` or the folder set in Settings. The package's own
  Hugging Face cache is not used. Every file is checked against the hash
  Hugging Face lists for it. The files land in a `.partial` folder that is
  renamed when complete, and a stopped download goes on where it stopped.
- **Speakers:** Vivian, Serena, Ono Anna, Sohee, Ryan, Aiden, Uncle Fu,
  Eric, Dylan. Each speaks all of its languages: English, German, Spanish,
  French, Italian, Portuguese, Russian, Japanese, Korean, Chinese. Eric and
  Dylan have a Sichuan and a Beijing accent in Chinese.
- **Moods:** the model takes `"speaker, instruction"` as its voice.
  `tts:mood` values become the instruction: known moods in a few words
  ("excited" becomes "very excited and energetic"), another word as
  "in a … way", and a phrase as it is written.
- **Speed:** the model has no speed setting, so its speech is stretched
  in time afterwards with Core Audio's time-pitch effect, without changing
  the pitch (`TimeStretch`).
- **Numbers:** digits make the model stumble or drift into another
  language. With Vivian reading English, "In 1848" came out as gibberish or
  Chinese in every run, and "Chapter 2" as "Chapter TOR". So numbers are
  written out in words first (`NumberSpeller`), in the language being read,
  with English years as years.
- **Sampling:** Qwen's own settings: temperature 0.9 and top-k 50. The
  package's defaults leave top-k out, which let the model wander. A
  transcription with Whisper of three runs of a long English text, read by
  a Chinese speaker, found no piece in another language with both fixes,
  and a third of the number-heavy pieces garbled without them.
- **Speed of making speech:** on an M1 Max, optimised, the 0.6B model makes
  14 seconds of speech in about 5 seconds, so playback keeps up. Unoptimised,
  it is slower than real time, which is why `./build.sh run` builds
  Release. Loading the model takes about 10 seconds; it is loaded when the
  engine is chosen, not when the first sentence is asked for.
- **Macs:** Apple silicon only. On an Intel Mac the engine offers no
  languages and its Settings section is hidden.

## ZipVoice and Pocket TTS as built

- **Models:** from sherpa-onnx's releases, through the sherpa-onnx already
  in the app. ZipVoice: `sherpa-onnx-zipvoice-distill-int8-zh-en-emilia`
  (104 MB), with the Vocos vocoder `vocos_24khz.onnx` (52 MB), which is
  published apart and put in the model's folder. Pocket TTS:
  `sherpa-onnx-pocket-tts-int8-2026-01-26` (94 MB). Each download is checked
  against its SHA-256, and goes into `~/.dysnow/voices` or the folder set in
  Settings.
- **Licences:** Pocket TTS's makers allow it for non-commercial use only;
  Settings says so.
- **Voices:** none of their own. They speak in the voice of a recording,
  the user's voices (`MyVoiceLibrary`), kept in `~/.dysnow/my-voices`: a
  folder per voice with its recordings, mono at 24 kHz, and a `voice.json`.
  A voice is recorded in the app or taken from a sound file. Silence at the
  ends is cut off, and the recording is kept to 15 seconds at most. Every
  voice speaks in every language of the model; the accent is the
  recording's.
- **Words of the recording:** ZipVoice needs them. Recording in the app
  shows a sentence to read; for a file, macOS's speech recognition writes
  them down, on the Mac, and they can be corrected. Pocket TTS does without.
- **Languages:** ZipVoice English and Chinese; Pocket TTS English.
- **Moods:** by example. A voice may have a recording per mood; a
  `tts:mood` with one is read in the manner of that recording. A mood with
  none is shown in pace and pauses, as for Kokoro
  (`MoodAwareEngine.knows(mood:for:)`).
- **Speed:** Pocket TTS ignores the speed it is given, and ZipVoice garbles
  the words at another speed than 1 (Whisper heard "In a kid real form and
  dang dang gay" at 1.5). Both make speech at speed 1, stretched afterwards
  like Qwen3-TTS's.
- **Numbers:** written out in words first, as for Qwen3-TTS.
- **Speed of making speech:** on an M1 Max, ZipVoice made 5.2 s of speech
  in 3.5 s, Pocket TTS 6.5 s in 2.1 s, the model loaded with the first.

## XTTS v2 as built

- **Why Python:** XTTS v2 is Coqui TTS's PyTorch model. It has no ONNX or
  MLX port that runs reliably, so Dysnow runs it in Python and talks to it.
  Dysnow brings no Python of its own.
- **Python:** 3.11 only. Several of Coqui TTS's dependencies do not build
  on 3.12 or newer. Dysnow looks in Homebrew's, python.org's, uv's, pyenv's
  and MacPorts' places, or uses one chosen in Settings, and checks the
  version and the processor kind. With none, it says how to install one:
  `brew install python@3.11`, `uv python install 3.11`, or python.org.
- **Libraries:** `Dysnow/XTTS/xtts-requirements.txt` pins the 155
  libraries known to work together on Apple silicon. They are taken from
  the working XTTS Voice Generator environment, without PyQt5. Dysnow makes
  `~/.dysnow/xtts/venv` and installs them with pip, about 2 GB and some
  minutes. A copy of the list in the environment marks it done; a Dysnow
  with another list installs again. An existing environment can be used
  instead, once its libraries load.
- **Server:** `Dysnow/XTTS/xtts_server.py`, in the app's resources. One
  line of JSON per request and per answer, on stdin and stdout: `check`,
  `load`, `speak` (writes a WAV file) and `quit`. What the libraries print
  goes to stderr. It is started when first needed and kept running, so the
  model is loaded once (about half a minute; requests made meanwhile wait
  for that load, and the status bar says so). It ends when Dysnow quits
  and its stdin closes.
- **Fixes needed with these versions:** `torch.load` must be told
  `weights_only=False` for XTTS's pickled checkpoint. torchaudio 2.11 reads
  files only through torchcodec, which is not installed, so reference
  recordings are read with soundfile instead.
- **Model:** `coqui/XTTS-v2` on Hugging Face, pinned to a commit. Only
  `config.json`, `model.pth`, `vocab.json`, `speakers_xtts.pth` and the
  licence are fetched, 1.9 GB, into `~/.dysnow/xtts/XTTS-v2`. A copy Coqui
  TTS already downloaded (`~/Library/Application Support/tts/…xtts_v2`) is
  used when Dysnow's own folder is empty. Licence: Coqui Public Model
  License, non-commercial only.
- **Voices:** the model's 58 speakers, every one in all 17 languages, and
  the user's own voices from My Voices, with their moods. The speakers'
  names are made up; their genders were taken from their speech with a
  gender classifier and pitch. Andrew Chipper, Badr Odhiambo and Suad Qasim
  are women's voices.
- **Speed:** XTTS's own `speed`.
- **Pieces:** XTTS ends each request abruptly, the last vowel falling silent
  within 20 or 30 ms. Inside a request it makes natural pauses between
  sentences itself. So it is given as many sentences at once as it reads
  well, 90% of its own character limit per language (224 for Hungarian, 82
  for Chinese), with only the first piece short so that playback starts soon
  (`TextChunker.packed`, `SpeechEngine.longestPiece`). XTTS has no limit of
  its own for Hindi and fails looking for one: the server sets 150.
- **Endings:** XTTS cuts the last sound of what it is given short, a
  vowel falling silent within 20 ms. Settings → XTTS v2 → Sentence Endings
  (`xtts.ending`, sent to the server as `ending`) chooses what is done:
  - *Cut short*: nothing.
  - *Faded out* (the default, `decayed`): when the level falls 30 dB within
    60 ms after a voiced sound, its last pitch period (autocorrelation over
    the last 40 ms, 70-400 Hz, at least 0.3) is repeated for 120 ms, fading
    with a 30 ms time constant. A short sound after silence at the very end,
    a click XTTS sometimes makes, is dropped. It is signal processing, not
    XTTS's own ending; Whisper heard the same words with it on 30 pieces in
    ten languages, but for two Hungarian endings.
  - *Last word said again* (experimental, `tail_of`, `tail_start`): the
    piece is ended with a full stop when it does not end a sentence, and
    XTTS says its last word again after it as a sentence of its own ("…
    senki sem bánta. Bánta."; in Japanese its last three characters).
    Dysnow cuts that off halfway into the pause before it, fading out over
    30 ms. The ending is then XTTS's own; when the cut misses, the word is
    heard twice rather than a word not in the text. The first version said
    "Igen." / "Yes." instead, which was heard when it slipped through. The pause is found by loudness:
    10 ms frames quieter than 30 dB below the loud ones, at least 120 ms,
    ending no further from the end than 3.5 times what the word should take
    by its length against the text's; the one long and quiet (length times
    depth) is taken. When another is a quarter as long and quiet, or there
    is none, the piece is said again; the second time it is faded out
    instead. Not in Chinese, where a comma pauses as long as a sentence's
    end and the cut came at a comma.
    A fixed cut, the word's length off the end, does not work: the same
    word takes 1.2 s or 1.9 s, and XTTS sometimes says more after it
    ("Alright? Alright?"), once for 15 s. Fingerprinting the word (MFCC and
    DTW against it said alone) was tried and did worse. Against Whisper's
    word times on 77 pieces (English, Hungarian, Spanish, Japanese) the
    rule found the right pause in all. On 68 new pieces in 16 languages, 2
    kept the word (Turkish, Polish: XTTS went on after it, so the pause
    before it was too far back to be looked for), and 1 Chinese piece was
    cut at a comma. Each piece takes longer: the word is half a second more
    to make, and an unclear piece is made twice.

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
