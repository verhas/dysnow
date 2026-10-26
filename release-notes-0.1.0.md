# Dysnow 0.1.0

The first build: text in, speech out, with Kokoro's natural voices,
Piper's in 47 languages, and Qwen3-TTS, which reads in the mood it is told.

- Open a text file, or type or paste text into the editor.
- The text is read as Markdown: headings, lists, links and emphasis without
  their symbols, code blocks skipped, and a pause between paragraphs.
- Choose the language, then a woman's or a man's voice, then the speaker,
  who says hello when picked.
- Play the text, the selection, or from the cursor.
- Markup in HTML comments sets the mood, the speaker, the speed and the
  language of parts of the text: see MARKUP.md. Control-Space helps write
  it, offering what fits where the cursor is.
- The text can be plain text instead of Markdown, chosen in the toolbar or
  by the file opened; its tags are in brackets.
- Save the speech as M4A, MP3, WAV, AIFF or FLAC. Files are made one after the
  other in a queue, with a notification when a long one is done.
- Kokoro's voice model is downloaded once, to `~/.dysnow/voices` or another
  folder, or an existing copy is used.
- Piper's 205 voices in 47 languages, Hungarian, Polish and Czech among
  them, browsed by language in Settings and each downloaded on its own, with
  its licence shown beside it. A language is offered once one of its voices
  is downloaded; Hungarian (Anna, Berta, Imre) always.
- XTTS v2, run in Python 3.11 found on the Mac: 58 speakers and your own
  voices, in 17 languages, Hungarian among them. Dysnow sets up its Python
  libraries in `~/.dysnow/xtts` when asked, and says how to install Python
  3.11 when there is none. XTTS cuts the last sound short; Dysnow fades it
  out, or, chosen in Settings, has XTTS say the last word again and cuts
  that off.
- Before any model is downloaded, a warning: following its licence is up to
  the user.
- Qwen3-TTS on Macs with Apple silicon: nine speakers in ten languages,
  German, Russian and Korean among them, told the mood of `tts:mood` tags in
  words. Its model, 1.9 or 2.9 GB, is downloaded once.
- Your own voices: made of a recording, made in the app or taken from a
  sound file, and read in by ZipVoice (English and Chinese) and Pocket TTS
  (English). A recording of a voice in a mood makes it speak in that mood.
- `tts:set` changes the language, the model, the speaker, the speed and the
  mood at once, from there on: English with Kokoro and Hungarian with Piper
  in one text, played and saved as one.
- Apple Intelligence can go through the text, fixing typos and writing out
  abbreviations, signs and sums as they are said: "e.g." as "for example",
  2*4 as "two times four".
- The editor shows what changed since the text was opened: changed and
  added words on a yellow ground, showing what was there when hovered, a red
  mark where text was deleted; right-click to restore or keep a change.
  New Text (⌘N) empties the editor, and the text pasted next is the one
  changes are shown against.
- Save the text (⌘S, ⇧⌘S); speech is saved with ⌥⌘S.
- Settings: what each model is good and bad at, and its licence, behind the
  (?) beside its name; the editor's font and size; a light, dark or system
  theme.
