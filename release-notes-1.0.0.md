# Dysnow 1.0.0

The first release: text in, speech out, read on the Mac by the models it
downloads, never in the cloud. Kokoro's natural voices, Piper's in 47
languages, Qwen3-TTS, which reads in the mood it is told, XTTS v2, and your
own voices.

## The text

- Open a text file or a Word document, type or paste text into the editor,
  or drop a file on the window. New Text (⌘N) starts afresh.
- The text is read as Markdown: headings, lists, links and emphasis without
  their symbols, code blocks skipped, and a pause between paragraphs. It can
  be plain text instead, chosen in the toolbar or by the file opened.
- The editor shows what changed since the text was opened or pasted:
  changed and added words on a yellow ground, showing what was there when
  hovered, a red mark where text was deleted; right-click to restore or
  keep a change.
- Apple Intelligence can go through the text, fixing typos and writing out
  abbreviations, signs and sums as they are said: "e.g." as "for example",
  2*4 as "two times four".
- Save the text (⌘S, ⇧⌘S).

## Speaking

- Choose the language, then a woman's or a man's voice, then the model and
  the speaker, who says hello when picked.
- Play the text, the selection, or from the cursor; pause and stop.
- Markup in HTML comments sets the mood, the speaker, the speed, the model
  and the language of parts of the text: see MARKUP.md. `tts:set` changes
  several at once, from there on: English with Kokoro and Hungarian with
  Piper in one text, played and saved as one. Control-Space helps write
  the tags, offering what fits where the cursor is, and closes the tags
  left open.
- Save the speech (⌥⌘S) as M4A, MP3, WAV, AIFF or FLAC. Files are made one
  after the other in a queue, with a notification when a long one is done.

## The models

- Kokoro: natural English voices, and others in seven more languages. Its
  model is downloaded once, to `~/.dysnow/voices` or another folder, or an
  existing copy is used.
- Piper: 205 voices in 47 languages, Hungarian, Polish and Czech among
  them, browsed by language in Settings and each downloaded on its own, with
  its licence shown beside it. Hungarian (Anna, Berta, Imre) is always
  offered; another language once one of its voices is downloaded.
- Qwen3-TTS, on Macs with Apple silicon: nine speakers in ten languages,
  told the mood of `tts:mood` tags in words. Its model, 1.9 or 2.9 GB, is
  downloaded once.
- XTTS v2: 58 speakers and your own voices in 17 languages, Hungarian among
  them. It runs in Python 3.11 found on the Mac -- Dysnow does not bring
  Python, and says how to install it when there is none -- with libraries
  Dysnow sets up in `~/.dysnow/xtts` when asked, or an environment you
  already have. Its model loads once after Dysnow starts, in about half a
  minute, and the status bar says so. XTTS cuts the last sound short;
  Dysnow fades it out, or, chosen in Settings, has XTTS say the last word
  again and cuts that off.
- Before any model is downloaded, a warning: following its licence is up to
  you.

## Your own voices

- Made of a recording, made in the app or taken from a sound file. The text
  to read is in the language chosen for the voice.
- Read in by XTTS v2 (17 languages), ZipVoice (English and Chinese) and
  Pocket TTS (English). A recording of a voice in a mood makes it speak in
  that mood.

## Settings

- What each model is good and bad at, and its licence, behind the (?)
  beside its name -- for information only, not legal advice.
- The models' downloads and folders; XTTS's Python, environment and how its
  sentences end.
- The editor's font and size; a light, dark or system theme.
