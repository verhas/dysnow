---
name: dysnow
description: Turn written text into speech -- a sound file (.m4a, .mp3, .wav, .aiff, .flac) or played aloud -- on this Mac with Dysnow, through its command line or its MCP server. Use when asked to read a text aloud, narrate a document, make a voice-over or an audio version of a text, or to choose a voice, language or speed for one.
---

# Making speech with Dysnow

Dysnow reads text aloud on the Mac, with speech models downloaded in the
Dysnow app; nothing is sent to the cloud. The app's executable is also a
command line tool and an MCP server:

```
/Applications/Dysnow.app/Contents/MacOS/Dysnow
```

It may be linked on the `PATH` as `dysnow`; check with `command -v dysnow`,
and use the full path above when it is not. The examples below write
`dysnow`.

Models are downloaded only in the app (its Settings). When a model or a voice
is missing, say so to the user: the command line cannot download one.

## Before speaking: what is there

```
dysnow models --json          # each model, whether it is installed, its language ids
dysnow voices --json          # every voice that can speak now
dysnow voices -l de --json    # those of a language; -m MODEL, -g female|male|neutral narrow it
```

A voice entry has `model`, `model_id`, `language`, `language_name`,
`voice`, `voice_id` and `gender`. Use what these list rather than guessing
names.

## Speaking

```
dysnow speak "Good morning." -o /abs/path/morning.m4a --json
dysnow speak -f chapter.md -l en-gb -v Fable -o /abs/path/chapter.mp3 --json
printf '%s' "$TEXT" | dysnow speak -l hu -o /abs/path/out.wav --json
dysnow speak --play "Done."   # plays it on the Mac's speakers, no file
```

| Option | Meaning |
|---|---|
| `-o, --output FILE` | The sound file; the extension picks the kind: `.m4a`, `.mp3`, `.wav`, `.aiff`, `.flac`. Needed unless `--play`. |
| `-p, --play` | Play the speech as it is made; may go with `-o`. |
| `-t, --text TEXT` / words | The text; or `-f FILE` (`.md`, `.txt`, `.docx`, `.rtf`), or the standard input (`-f -`). |
| `-l, --language L` | Id or name: `en-us`, `en-gb`, `de`, `German`, `Hungarian`. |
| `-v, --voice NAME` | A voice's name or id, from `dysnow voices`. |
| `-m, --model NAME` | `kokoro`, `piper`, `qwen3`, `xtts`, `zipvoice`, `pocket`; the start of a name will do. |
| `-g, --gender G` | `female`, `male` or `neutral`. |
| `-s, --speed X` | 0.25 to 4; 1 is the voice's own pace (the default). |
| `--plain` | The text is plain text, not Markdown. |
| `--json` | Print the result as one line of JSON. |
| `-q, --quiet` | Nothing on stderr but errors. |

With `--json`, the standard output is exactly one line:

```json
{"duration":4.41,"language":"en-gb","language_name":"English (UK)","model":"Kokoro",
 "output":"/abs/path/morning.m4a","sample_rate":24000,"voice":"Alice","voice_id":"bf_alice","warnings":[]}
```

Without it, the standard output is the path of the file written. Progress
and warnings go to stderr. Exit status: 0 done, 1 the speech could not be
made (the reason is on stderr), 2 the command was wrong.

Good habits:

- Give absolute output paths; the directory is made if it is not there.
- Pass long or quoted text through a file or the standard input, not as an
  argument, so the shell does not mangle it.
- Name the language when it is not the one the user's app is set to:
  what is not given -- language, model, voice -- is as last chosen in the
  app, so it differs between machines. Check `language`, `model` and
  `voice` in the result.
- Read `warnings`: they say what markup in the text could not be followed
  (a speaker not downloaded, a language no model speaks).
- Speech takes time: from a fraction of the text's reading time with Kokoro
  and Piper to longer with Qwen3-TTS; XTTS v2 first loads its model for
  about half a minute. Allow a long timeout for long texts.

## The text and its markup

The text is read as Markdown: headings, lists and emphasis are read without
their symbols, code blocks are skipped, paragraphs are followed by a pause.
Tags in HTML comments change how a part is read; a Markdown viewer does not
show them:

```markdown
<!-- tts:mood value="excited" -->We won!<!-- /tts:mood -->
<!-- tts:speed value="0.8" -->Slowly now.<!-- /tts:speed -->
<!-- tts:speaker value="Fable" -->A second voice.<!-- /tts:speaker -->
<!-- tts:language value="German" -->Guten Tag.<!-- /tts:language -->
<!-- tts:set language="Hungarian" model="piper" speaker="Anna" -->
From here on, read in Hungarian by Piper's Anna.
```

`tts:set` changes several things at once and stays until the next one or
its closing tag. In plain text (`--plain`) the tags are in brackets:
`[tts:mood value="sad"] ... [/tts:mood]`. Moods are told to Qwen3-TTS, and to
the user's own voices recorded in that mood; other models show them in pace
and pauses. `MARKUP.md` in the Dysnow repository has the details.

Write numbers, abbreviations and symbols the way they are to be said when
it matters: "for example" rather than "e.g.".

## MCP

`dysnow mcp` serves the Model Context Protocol over the standard input and
output. To add it to Claude Code:

```
claude mcp add dysnow -- /Applications/Dysnow.app/Contents/MacOS/Dysnow mcp
```

Other clients:

```json
{ "mcpServers": { "dysnow": {
    "command": "/Applications/Dysnow.app/Contents/MacOS/Dysnow", "args": ["mcp"] } } }
```

Tools:

- `speak` -- `text` or `input_path`; `output_path` (absolute; without it, a
  new file in the temporary directory, of `audio_format`: m4a, mp3, wav,
  aiff, flac); and optionally `language`, `voice`, `model`, `gender`,
  `speed`, `text_format` (`markdown` or `plain`), `return_audio` (also
  return the sound, base64). Returns when the file is written; the
  structured result is the JSON the command line prints. A failure comes
  back as a result with `isError` and the reason.
- `list_voices` -- `language`, `model`, `gender`, all optional.
- `list_models`.

Requests are answered one at a time: a long `speak` holds up the next call.
Relative paths are taken from the server's working directory, so give
absolute ones.
