# Dysnow

Dysnow is a macOS app that reads text aloud. Open or paste a text, choose a
language and a voice, and play it or save it as a sound file. The speech is
made on the Mac, by models Dysnow downloads; no text is sent to the cloud.

The name came first; the words to fit it came after. Dysnow stands for
**Dy**namic **S**peech, **N**uance, **O**rchestrated for **W**ords.

## What it does

- Reads Markdown or plain text: headings, lists and emphasis without their
  symbols, code blocks skipped, a pause between paragraphs. It opens text
  files and Word documents.
- Plays the whole text, the selection, or from the cursor, and saves the
  speech as M4A, MP3, WAV, AIFF or FLAC.
- Tags in the text change the mood, the speaker, the speed, the language or
  the model for a part of it. In Markdown the tags are HTML comments, so the
  document reads the same without them. Control-Space helps write them. See
  [MARKUP.md](MARKUP.md).
- Apple Intelligence can go through the text first, fixing typos and
  writing out abbreviations and signs as they are said. The editor shows
  what changed.
- Your own voices: record one in the app, or take one from a sound file, and
  have the text read in it.

## Speech models

| Model | Languages | Notes |
|---|---|---|
| Kokoro | English and 7 more | Natural voices; one download |
| Piper | 47 | 205 voices, each downloaded on its own; Hungarian always offered |
| Qwen3-TTS | 10 | Apple silicon; reads in the mood it is told |
| XTTS v2 | 17 | 58 speakers and your own voices; runs in Python 3.11 on the Mac |
| ZipVoice, Pocket TTS | English, Chinese | Your own voices |

Each model has its own licence, shown in Settings and before it is
downloaded; some allow non-commercial use only. Following them is up to the
user. [ENGINES.md](ENGINES.md) describes how each model is used and what
else was considered.

## Requirements

- macOS 26 or later.
- XTTS v2 only: Python 3.11, from Homebrew (`brew install python@3.11`),
  uv or python.org. Dysnow does not bring Python; it sets up the
  libraries XTTS needs in `~/.dysnow/xtts` when asked.

## Building

With Xcode installed:

```
./build.sh run      # build and start the app
./build.sh test     # run the tests
./build.sh --help   # every command, including making a signed, notarized .dmg
```

The first build fetches sherpa-onnx and builds LAME into `Vendor/`.

## Licence

Apache License 2.0; see [LICENSE](LICENSE). The speech models are not part
of Dysnow and come under their own licences.
