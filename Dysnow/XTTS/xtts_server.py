"""Dysnow's XTTS v2 speaker: Coqui's XTTS v2 model, run in Python, as Swift
cannot run it. Dysnow starts it with the Python of the environment it set up
for it, ~/.dysnow/xtts/venv, and talks to it a line of JSON at a time:
requests on stdin, answers on stdout. Whatever the libraries print goes to
stderr, which Dysnow shows when something goes wrong.

Every request has an "id", which its answer repeats, and a "command":

    {"id": 1, "command": "check"}
        Whether the libraries load: {"ok": true, "python": "3.11.15",
        "torch": "...", "tts": "0.22.0"}.
    {"id": 2, "command": "load", "model": "/path/to/XTTS-v2"}
        Loads the model from its folder: config.json, model.pth, vocab.json,
        speakers_xtts.pth. Answers {"ok": true, "speakers": [...],
        "languages": [...], "sample_rate": 24000}.
    {"id": 3, "command": "speak", "text": "...", "language": "en",
     "speaker": "Ana Florence" | "reference": ["/path/sample.wav"],
     "speed": 1.0, "ending": "fade", "output": "/path/out.wav"}
        Writes the speech to "output", a 16-bit mono WAV file, in a
        built-in speaker's voice or in that of the reference recordings.
        "ending" is how its end is made, as XTTS cuts the last sound short:
        "cut" leaves it so, "fade" makes it die away, "word" has XTTS say
        the last word again and cuts that off (see `say`).
        Answers {"ok": true, "output": "...", "seconds": 2.4}.
    {"id": 4, "command": "quit"}

A request that fails is answered {"id": ..., "ok": false, "error": "..."}.
When it starts it says {"event": "ready"}.
"""

import json
import os
import sys
import traceback
import unicodedata
import wave

# The answers go to the real stdout; what the libraries print, to stderr.
_answers = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
os.dup2(2, 1)
sys.stdout = sys.stderr


def send(**message):
    _answers.write(json.dumps(message, ensure_ascii=False) + "\n")
    _answers.flush()


model = None
# Conditioning latents of reference recordings, by their paths and times.
latents = {}


def check(_request):
    import platform

    import torch
    import TTS

    return {"python": platform.python_version(), "torch": torch.__version__, "tts": TTS.__version__}


def load(request):
    global model
    import torch

    # XTTS v2's checkpoint is pickled: recent PyTorch refuses it unless told
    # it is trusted. Only the model Dysnow downloads, checked against its
    # hashes, or one the user chose, is loaded.
    original = torch.load

    def trusted(*args, **kwargs):
        kwargs.setdefault("weights_only", False)
        return original(*args, **kwargs)

    torch.load = trusted

    from TTS.tts.configs.xtts_config import XttsConfig
    from TTS.tts.models import xtts
    from TTS.tts.models.xtts import Xtts

    # Recent torchaudio reads files only with torchcodec, which is not
    # installed: the recordings are read with soundfile instead.
    xtts.load_audio = read_audio

    folder = request["model"]
    config = XttsConfig()
    config.load_json(os.path.join(folder, "config.json"))
    loaded = Xtts.init_from_config(config)
    loaded.load_checkpoint(config, checkpoint_dir=folder, eval=True, use_deepspeed=False)
    loaded.to("cpu")
    # XTTS has no length limit for Hindi, and fails looking for one.
    loaded.tokenizer.char_limits.setdefault("hi", 150)
    model = loaded
    latents.clear()
    speakers = sorted(model.speaker_manager.speakers.keys()) if model.speaker_manager else []
    return {"speakers": speakers, "languages": list(config.languages),
            "sample_rate": config.audio.output_sample_rate}


def read_audio(path, sampling_rate):
    """A recording as XTTS wants it: mono, at `sampling_rate`, from -1 to 1."""
    import soundfile
    import torch
    import torchaudio

    data, rate = soundfile.read(path, dtype="float32", always_2d=True)
    audio = torch.from_numpy(data.T.copy()).mean(dim=0, keepdim=True)
    if rate != sampling_rate:
        audio = torchaudio.functional.resample(audio, rate, sampling_rate)
    return audio.clip(-1, 1)


def conditioning(request):
    if request.get("reference"):
        paths = request["reference"]
        key = tuple((path, os.path.getmtime(path)) for path in paths)
        if key not in latents:
            latents[key] = model.get_conditioning_latents(audio_path=paths)
        return latents[key]
    speaker = request.get("speaker")
    if not speaker or speaker not in model.speaker_manager.speakers:
        raise ValueError(f"There is no speaker {speaker!r} in the model.")
    voice = model.speaker_manager.speakers[speaker]
    return voice["gpt_cond_latent"], voice["speaker_embedding"]


def speak(request):
    if model is None:
        raise RuntimeError("The model is not loaded.")
    import numpy

    gpt_cond_latent, speaker_embedding = conditioning(request)
    language = request["language"]
    speed = float(request.get("speed", 1.0))
    rate = model.config.audio.output_sample_rate
    ending = request.get("ending", "fade")
    samples = numpy.concatenate([say(part, language, gpt_cond_latent, speaker_embedding, speed, ending)
                                 for part in parts(request["text"].strip(), language)])
    pcm = (numpy.clip(samples, -1, 1) * 32767).astype("<i2")
    with wave.open(request["output"], "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(rate)
        file.writeframes(pcm.tobytes())
    return {"output": request["output"], "seconds": len(samples) / rate}


# XTTS ends what it says abruptly: the last sound is cut short, a vowel in
# 20 ms. Between sentences it ends them well. So the text's last word is
# said again after it, as a sentence of its own -- "... senki sem bánta.
# Bánta." -- and cut off at the pause before it: when it is not cut off, it
# is at least a word of the text. Not in Chinese: there a comma pauses as
# long as a sentence's end, and the cut came at a comma.
WITHOUT_TAIL = {"zh-cn"}
SENTENCE_ENDS = tuple(".!?…。！？؟।")
QUOTES = "\"'”’»)"
FULL_STOPS = {"ja": "。", "hi": "।"}


def parts(text, language):
    """The text in parts XTTS reads at once, each with room for the tail:
    a word, or in Japanese a few characters."""
    from TTS.tts.layers.xtts.tokenizer import split_sentence

    limit = model.tokenizer.char_limits.get(language, 250) - (4 if language == "ja" else 25)
    return split_sentence(text, language, limit) if len(text) >= limit else [text]


def ended(text, language):
    """The text ending a sentence: with a full stop when it does not. A
    quote closed after the sentence's end, ".”", ends it too."""
    return text if text.rstrip(QUOTES).endswith(SENTENCE_ENDS) else text + FULL_STOPS.get(language, ".")


def tail_of(text, language):
    """The text's last word as a sentence of its own, "Bánta."; None when
    it has no word. Japanese is written without spaces: its last three
    characters are taken."""
    words = text.split()
    word = words[-1] if words else ""
    # Punctuation and symbols off its ends; letters with their marks kept.
    while word and unicodedata.category(word[-1])[0] in "PSZ":
        word = word[:-1]
    while word and unicodedata.category(word[0])[0] in "PSZ":
        word = word[1:]
    if language == "ja":
        word = word[-3:]
    if not word:
        return None
    return word[:1].upper() + word[1:] + FULL_STOPS.get(language, ".")


def say(text, language, gpt_cond_latent, speaker_embedding, speed, ending):
    """The text said, its end made as `ending` asks."""
    import numpy

    def inference(text):
        import torch

        with torch.inference_mode():
            out = model.inference(text, language, gpt_cond_latent, speaker_embedding, speed=speed,
                                  enable_text_splitting=False)
        return numpy.asarray(out["wav"], dtype=numpy.float32)

    rate = model.config.audio.output_sample_rate
    if ending == "cut":
        return inference(text)
    if ending != "word" or language in WITHOUT_TAIL:
        return decayed(inference(text), rate)
    # A sentence's end makes the pause before the tail to cut at.
    text = ended(text, language)
    tail = tail_of(text, language)
    if tail is None:
        return decayed(inference(text), rate)
    # XTTS says it differently each time: when it is not clear where the
    # tail starts, it is said once more; then without the tail, faded out,
    # rather than keep a word said twice. That is not certain either: when
    # XTTS says more after the tail, the pause before it may be too far
    # back to be looked for, and the tail is kept.
    for _ in range(2):
        samples = inference(text + " " + tail)
        end = tail_start(samples, len(text), len(tail), rate)
        if end is not None:
            return faded(samples[:end], rate)
    print(f"Not clear where the tail of {text[-40:]!r} starts: said without it.", file=sys.stderr)
    return decayed(inference(text), rate)


def tail_start(samples, text_length, tail_length, rate):
    """Where to cut the tail off: halfway into the pause before it, at most
    150 ms in, so that a quiet last sound is kept; None when there is no
    such pause, or more than one could be it.

    The pause is looked for where the tail should start, by how long it is
    against the text: a sentence's end pauses long, often in silence, so
    the pause there is long and quiet. A comma pauses shorter; a pause
    after the tail, when XTTS said more, is as long."""
    import numpy

    frame = rate // 100
    count = len(samples) // frame
    if count == 0:
        return None
    power = (samples[:count * frame].reshape(count, frame) ** 2).mean(axis=1)
    level = 10 * numpy.log10(power + 1e-12)
    quiet = level < numpy.percentile(level, 90) - 30
    loud = numpy.nonzero(~quiet)[0]
    if len(loud) == 0:
        return None
    speech_end = loud[-1] + 1
    expected = max(speech_end * tail_length / (text_length + 1 + tail_length), 30)
    candidates = [(start, stop) for start, stop in pauses(quiet[:speech_end])
                  if start > 0 and 5 <= speech_end - stop <= 3.5 * expected]

    def score(pause):
        start, stop = pause
        return (stop - start) * -level[start:stop].mean()

    best = max(map(score, candidates), default=0)
    likely = [pause for pause in candidates if score(pause) >= 0.25 * best]
    if len(likely) != 1:
        return None
    start, stop = likely[0]
    return (start + min(15, (stop - start) // 2)) * frame


def pauses(quiet, shortest=12, bridge=5):
    """The runs of quiet frames at least `shortest` long, those apart by no
    more than `bridge` frames joined: as (start, stop) pairs."""
    runs = []
    start = None
    for index, value in enumerate(list(quiet) + [False]):
        if value and start is None:
            start = index
        elif not value and start is not None:
            if runs and start - runs[-1][1] <= bridge:
                runs[-1] = (runs[-1][0], index)
            else:
                runs.append((start, index))
            start = None
    return [(start, stop) for start, stop in runs if stop - start >= shortest]


def decayed(samples, rate):
    """The samples, a voiced last sound cut short made to die away: its
    last pitch period repeated, fading out over 120 ms. An end that already
    fades, or is not voiced, is left as it is. A click XTTS sometimes makes
    after the end, a short sound after silence, is dropped."""
    import numpy

    frame = rate // 100
    count = len(samples) // frame
    if count < 10:
        return samples
    level = 10 * numpy.log10((samples[:count * frame].reshape(count, frame) ** 2).mean(axis=1) + 1e-12)
    loud = numpy.nonzero(level > numpy.percentile(level, 90) - 40)[0]
    if len(loud) == 0 or loud[-1] < 8:
        return samples
    # A sound of at most 80 ms after 100 ms of silence: a click.
    gaps = numpy.nonzero(numpy.diff(loud) > 10)[0]
    if len(gaps) and loud[-1] - loud[gaps[-1] + 1] < 8:
        samples = samples[:loud[gaps[-1] + 1] * frame]
        count = len(samples) // frame
        level = level[:count]
        loud = loud[:gaps[-1] + 1]
    if loud[-1] < 8:
        return samples
    last = loud[-1]
    # The level the sound had before it ends, and the last frame still
    # near it: cut short when it falls 30 dB within 60 ms after that.
    reference = level[last - 8:last - 3].mean()
    if reference < numpy.percentile(level, 90) - 20:
        return samples
    held = [index for index in range(last - 8, last + 1) if level[index] >= reference - 6]
    if not held:
        return samples
    kept = held[-1]
    after = level[kept + 1:kept + 7]
    if len(after) and after.min() > reference - 30:
        return samples
    end = (kept + 1) * frame
    # Its pitch period, by autocorrelation over the last 40 ms.
    window = samples[max(0, end - rate * 4 // 100):end]
    shortest, longest = rate // 400, rate // 70
    if len(window) < 2 * longest:
        return samples
    def correlation(lag):
        later, earlier = window[lag:], window[:-lag]
        return float((later * earlier).sum() / (numpy.sqrt((later ** 2).sum() * (earlier ** 2).sum()) + 1e-12))

    correlations = [correlation(lag) for lag in range(shortest, longest)]
    best = int(numpy.argmax(correlations))
    if correlations[best] < 0.3:
        return samples
    period = samples[end - (shortest + best):end]
    length = rate * 12 // 100
    tail = numpy.tile(period, length // len(period) + 1)[:length]
    time = numpy.arange(length) / rate
    envelope = numpy.exp(-time / 0.03)
    envelope[-frame:] *= numpy.linspace(1, 0, frame)
    return numpy.concatenate([samples[:end], tail * envelope]).astype(numpy.float32)


def faded(samples, rate):
    """The samples, their last 30 ms faded out: no click where cut."""
    import numpy

    length = min(len(samples), rate * 3 // 100)
    if length:
        samples = samples.copy()
        samples[-length:] *= 0.5 + 0.5 * numpy.cos(numpy.linspace(0, numpy.pi, length))
    return samples


COMMANDS = {"check": check, "load": load, "speak": speak}


def main():
    send(event="ready")
    for line in sys.stdin:
        if not line.strip():
            continue
        request_id = None
        try:
            request = json.loads(line)
            request_id = request.get("id")
            command = request.get("command")
            if command == "quit":
                send(id=request_id, ok=True)
                return
            if command not in COMMANDS:
                raise ValueError(f"Unknown command {command!r}.")
            send(id=request_id, ok=True, **COMMANDS[command](request))
        except Exception as error:
            traceback.print_exc()
            send(id=request_id, ok=False, error=f"{type(error).__name__}: {error}")


if __name__ == "__main__":
    main()
