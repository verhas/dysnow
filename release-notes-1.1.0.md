# Dysnow 1.1.0

Dysnow can now be used without its window: from the command line, from
scripts, and by AI agents through the Model Context Protocol.

## The command line

- The app's executable is also a command line tool. Link it on the `PATH`
  once: `ln -s /Applications/Dysnow.app/Contents/MacOS/Dysnow
  /usr/local/bin/dysnow`.
- `dysnow speak` reads a text -- given as words, in a file, or on the
  standard input -- and saves the speech as M4A, MP3, WAV, AIFF or FLAC, or
  plays it. The language, the model, the voice, the gender and the speed
  can be named; what is not is as chosen in the app last. The text is read
  as Markdown, speech tags and all, or as plain text.
- `dysnow voices` lists the voices that can speak now, by language, model
  or gender; `dysnow models` the models and whether they are installed.
- Only the result goes to the standard output: the path of the file
  written, or a line of JSON with `--json`. The exit status says whether
  it worked; the reason goes to the standard error when it did not.
- `dysnow help` lists the commands, `dysnow help speak` every option.

## For agents

- `dysnow mcp` serves the Model Context Protocol on the standard input and
  output, with the tools `speak`, `list_voices` and `list_models`. In
  Claude Code: `claude mcp add dysnow --
  /Applications/Dysnow.app/Contents/MacOS/Dysnow mcp`.
- `speak` writes the sound file and returns when it is done, with its
  length and the voice that read it; it can return the sound itself too.
- DYSNOW-SKILL.md, in the repository, is a skill that tells an agent how to
  use the command line and the MCP server.

The models are still downloaded in the app; the command line and MCP use
those there are.
