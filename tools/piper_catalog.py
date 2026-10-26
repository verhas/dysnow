#!/usr/bin/env python3
"""Writes Dysnow/Speech/PiperCatalog.swift: every Piper voice sherpa-onnx
publishes, by language, with its checksum, size, licence and gender.

    python3 tools/piper_catalog.py CACHE_DIR > Dysnow/Speech/PiperCatalog.swift

CACHE_DIR keeps what is downloaded (with /usr/bin/curl): the list of
sherpa-onnx's tts-models release, Piper's voices.json and the model cards.
Delete it to fetch them again.

Neither source says whether a voice is a woman's or a man's: GENDERS below
does. It was filled in from the voices' names and speaker lists, and, where
those do not tell, from each voice's sample recording: its pitch and
formants, and a wav2vec2 gender classifier. A voice missing from it stops the
script.
"""

import hashlib
import json
import os
import re
import subprocess
import sys

RELEASE = "https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/tags/tts-models"
VOICES = "https://huggingface.co/rhasspy/piper-voices/resolve/main/voices.json"
HF = "https://huggingface.co/rhasspy/piper-voices"
SHERPA = "https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models"
QUALITIES = ["x_low", "low", "medium", "high"]

# The languages, as the app's other models name them where they share one.
LANGUAGES = {
    "en_US": ("en-us", "English (US)"), "en_GB": ("en-gb", "English (UK)"),
    "pt_BR": ("pt-br", "Portuguese (Brazil)"), "pt_PT": ("pt-pt", "Portuguese (Portugal)"),
    "es_ES": ("es", "Spanish"), "es": ("es", "Spanish"), "es_MX": ("es-mx", "Spanish (Mexico)"),
    "es_AR": ("es-ar", "Spanish (Argentina)"), "nl_NL": ("nl", "Dutch"), "nl_BE": ("nl-be", "Dutch (Belgium)"),
    "zh_CN": ("zh", "Chinese (Mandarin)"), "fa_IR": ("fa", "Persian"), "fa": ("fa", "Persian"),
    "fa_en": ("fa", "Persian"),
    # The Sorbian Institute's voices: Lower and Upper Sorbian, not Serbian.
    "sr_RS": ("wen", "Sorbian"),
    "sw_CD": ("sw", "Swahili"), "ku_TR": ("ku", "Kurdish"), "ar_JO": ("ar", "Arabic"),
    "lb_LU": ("lb", "Luxembourgish"), "no_NO": ("no", "Norwegian"),
}

FEMALE, MALE, NEUTRAL = "female", "male", "neutral"

# Per model, the gender of its first speaker. Models with more speakers have
# them in SPEAKERS.
GENDERS = {
    "ar_JO-kareem": MALE, "ar_JO-SA_dii": FEMALE, "ar_JO-SA_miro": MALE, "ar_JO-SA_miro_V2": MALE,
    "ca_ES-upc_ona": FEMALE, "ca_ES-upc_pau": MALE, "cs_CZ-jirka": MALE,
    "cy_GB-bu_tts": FEMALE, "cy_GB-gwryw_gogleddol": MALE, "da_DK-talesyntese": MALE,
    "de_DE-dii": FEMALE, "de_DE-eva_k": FEMALE, "de_DE-glados": FEMALE, "de_DE-glados_turret": FEMALE,
    "de_DE-karlsson": MALE, "de_DE-kerstin": FEMALE, "de_DE-miro": MALE, "de_DE-pavoque": MALE,
    "de_DE-ramona": FEMALE, "de_DE-thorsten": MALE, "de_DE-thorsten_emotional": MALE,
    "el_GR-rapunzelina": FEMALE,
    "en_GB-alan": MALE, "en_GB-alba": FEMALE, "en_GB-aru": FEMALE, "en_GB-cori": FEMALE,
    "en_GB-dii": FEMALE, "en_GB-jenny_dioco": FEMALE, "en_GB-miro": MALE,
    "en_GB-northern_english_male": MALE, "en_GB-semaine": FEMALE,
    "en_GB-southern_english_female": FEMALE, "en_GB-southern_english_male": MALE,
    "en_GB-sweetbbak-amy": FEMALE, "en_GB-vctk": FEMALE,
    "en_US-amy": FEMALE, "en_US-arctic": MALE, "en_US-bryce": MALE, "en_US-danny": MALE,
    "en_US-glados": FEMALE, "en_US-hfc_female": FEMALE, "en_US-hfc_male": MALE, "en_US-joe": MALE,
    "en_US-john": MALE, "en_US-kathleen": FEMALE, "en_US-kristin": FEMALE, "en_US-kusal": MALE,
    "en_US-l2arctic": MALE, "en_US-lessac": FEMALE, "en_US-libritts": FEMALE, "en_US-libritts_r": FEMALE,
    "en_US-ljspeech": FEMALE, "en_US-miro": MALE, "en_US-norman": MALE, "en_US-reza_ibrahim": MALE,
    "en_US-ryan": MALE, "en_US-sam": NEUTRAL,
    "es-glados": FEMALE, "es_AR-daniela": FEMALE, "es_ES-carlfm": MALE, "es_ES-davefx": MALE,
    "es_ES-glados": FEMALE, "es_ES-miro": MALE, "es_ES-sharvard": MALE, "es_MX-ald": MALE,
    "es_MX-claude": FEMALE,
    "eu_ES-antton": MALE, "eu_ES-maider": FEMALE,
    "fa-haaniye": FEMALE, "fa_en-rezahedayatfar-ibrahimwalk": MALE, "fa_IR-amir": MALE,
    "fa_IR-ganji": MALE, "fa_IR-ganji_adabi": MALE, "fa_IR-gyro": MALE, "fa_IR-reza_ibrahim": MALE,
    "fi_FI-harri": MALE,
    "fr_FR-gilles": MALE, "fr_FR-miro": MALE, "fr_FR-siwis": FEMALE, "fr_FR-tjiho": MALE,
    "fr_FR-tom": MALE, "fr_FR-upmc": FEMALE,
    "hi_IN-pratham": MALE, "hi_IN-priyamvada": FEMALE, "hi_IN-rohan": MALE,
    "hu_HU-anna": FEMALE, "hu_HU-berta": FEMALE, "hu_HU-imre": MALE,
    "id_ID-news_tts": FEMALE,
    "is_IS-bui": MALE, "is_IS-salka": FEMALE, "is_IS-steinn": MALE, "is_IS-ugla": FEMALE,
    "it_IT-dii": FEMALE, "it_IT-miro": MALE, "it_IT-paola": FEMALE, "it_IT-riccardo": MALE,
    "ka_GE-natia": FEMALE,
    "kk_KZ-iseke": MALE, "kk_KZ-issai": MALE, "kk_KZ-raya": FEMALE,
    "ku_TR-berfin_renas": FEMALE, "lb_LU-marylux": FEMALE, "lv_LV-aivars": MALE,
    "ml_IN-arjun": MALE, "ml_IN-meera": FEMALE,
    "ne_NP-chitwan": MALE, "ne_NP-google": FEMALE,
    "nl_BE-nathalie": FEMALE, "nl_BE-rdh": MALE, "nl_NL-alex": MALE, "nl_NL-dii": FEMALE,
    "nl_NL-miro": MALE, "nl_NL-pim": MALE, "nl_NL-ronnie": MALE,
    "no_NO-talesyntese": MALE,
    "pl_PL-bass": MALE, "pl_PL-darkman": MALE, "pl_PL-gosia": FEMALE, "pl_PL-jarvis_wg_glos": MALE,
    "pl_PL-justyna_wg_glos": FEMALE, "pl_PL-mc_speech": MALE, "pl_PL-meski_wg_glos": MALE,
    "pl_PL-zenski_wg_glos": FEMALE,
    "pt_BR-cadu": MALE, "pt_BR-dii": FEMALE, "pt_BR-edresson": MALE, "pt_BR-faber": MALE,
    "pt_BR-jeff": MALE, "pt_BR-miro": MALE, "pt_PT-dii": FEMALE, "pt_PT-miro": MALE,
    "pt_PT-tugao": MALE,
    "ro_RO-mihai": MALE,
    "ru_RU-denis": MALE, "ru_RU-dmitri": MALE, "ru_RU-irina": FEMALE, "ru_RU-ruslan": MALE,
    "sk_SK-lili": FEMALE, "sl_SI-artur": MALE, "sq_AL-edon": MALE, "sr_RS-serbski_institut": MALE,
    "sv_SE-alma": FEMALE, "sv_SE-lisa": FEMALE, "sv_SE-nst": MALE, "sw_CD-lanfrica": MALE,
    "tr_TR-dfki": MALE, "tr_TR-fahrettin": MALE, "tr_TR-fettah": MALE,
    "uk_UA-lada": FEMALE, "uk_UA-ukrainian_tts": FEMALE, "ur_PK-fasih": MALE,
    "vi_VN-25hours_single": FEMALE, "vi_VN-vais1000": FEMALE, "vi_VN-vivos": FEMALE,
    "zh_CN-chaowen": MALE, "zh_CN-huayan": FEMALE, "zh_CN-xiao_ya": FEMALE,
}

# The speakers offered of models with several, whose speakers say who they
# are: name, gender, speaker number. The first is the one in GENDERS.
SPEAKERS = {
    "de_DE-thorsten_emotional": [("Thorsten (emotional)", MALE, 4)],
    "es_ES-sharvard": [("Sharvard", MALE, 0), ("Sharvard (woman)", FEMALE, 1)],
    "fr_FR-upmc": [("Jessica", FEMALE, 0), ("Pierre", MALE, 1)],
    "ku_TR-berfin_renas": [("Berfin", FEMALE, 0), ("Renas", MALE, 1)],
    "uk_UA-ukrainian_tts": [("Lada (Ukrainian TTS)", FEMALE, 0), ("Mykyta", MALE, 1), ("Tetiana", FEMALE, 2)],
    "en_GB-semaine": [("Prudence", FEMALE, 0), ("Spike", MALE, 1), ("Obadiah", MALE, 2), ("Poppy", FEMALE, 3)],
    "sr_RS-serbski_institut": [("Lower Sorbian", MALE, 0), ("Upper Sorbian", MALE, 1)],
    "kk_KZ-issai": [("Issai M2", MALE, 0), ("Iseke (Issai)", MALE, 1), ("Issai F3", FEMALE, 2),
                    ("Raya (Issai)", FEMALE, 3), ("Issai F1", FEMALE, 4), ("Issai F2", FEMALE, 5)],
    "cy_GB-bu_tts": [("Benyw, de", FEMALE, 0), ("Benyw, gogledd", FEMALE, 1), ("Gwryw, gogledd", MALE, 2),
                     ("Gwryw, gogledd 2", MALE, 3), ("Gwryw, de", MALE, 4), ("Gwryw, gogledd 1", MALE, 5),
                     ("Benyw, gogledd 1", FEMALE, 6)],
}

NAMES = {
    "upc_ona": "Ona", "upc_pau": "Pau", "hfc_female": "HFC Female", "hfc_male": "HFC Male",
    "eva_k": "Eva K", "25hours_single": "25hours", "news_tts": "News", "mc_speech": "MC Speech",
    "zenski_wg_glos": "Żeński", "meski_wg_glos": "Męski", "jarvis_wg_glos": "Jarvis",
    "justyna_wg_glos": "Justyna", "libritts_r": "LibriTTS-R", "libritts": "LibriTTS", "ljspeech": "LJSpeech",
    "l2arctic": "L2-ARCTIC", "arctic": "ARCTIC", "vctk": "VCTK", "glados": "GLaDOS",
    "glados_turret": "GLaDOS Turret", "sweetbbak-amy": "Amy (sweetbbak)", "SA_dii": "Dii (Saudi)",
    "SA_miro": "Miro (Saudi)", "SA_miro_V2": "Miro 2 (Saudi)", "rezahedayatfar-ibrahimwalk": "Reza Hedayatfar",
    "reza_ibrahim": "Reza Ibrahim", "ganji_adabi": "Ganji Adabi", "vais1000": "VAIS1000",
    "vivos": "VIVOS", "aru": "ARU", "dfki": "DFKI", "nst": "NST", "rdh": "RDH", "bu_tts": "BU TTS",
    "gwryw_gogleddol": "Gwryw Gogleddol", "talesyntese": "Talesyntese", "lanfrica": "Lanfrica",
    "xiao_ya": "Xiao Ya", "chaowen": "Chaowen", "huayan": "Huayan", "tugao": "Tugão", "issai": "Issai",
    "jenny_dioco": "Jenny Dioco", "northern_english_male": "Northern English Male",
    "southern_english_female": "Southern English Female", "southern_english_male": "Southern English Male",
    # The voice's licence asks for its author not to be named where it is used.
    "tjiho": "Voix",
    "dii": "Dii", "miro": "Miro", "sharvard": "Sharvard", "carlfm": "Carlfm", "davefx": "Davefx",
}

# What the model cards of the voices sherpa-onnx converts itself say, or
# their READMEs.
OTHER_LICENCES = {
    "dii": ("CC BY-NC-SA 4.0: non-commercial", "https://huggingface.co/OpenVoiceOS"),
    "miro": ("CC BY-NC-SA 4.0: non-commercial", "https://huggingface.co/OpenVoiceOS"),
    "tjiho": ("AGPL-3.0, and conditions on the use of the voice: see the source",
              "https://github.com/tjiho/French-tts-model-piper"),
    "tugao": ("CC0", "https://github.com/OHF-Voice/voice-datasets"),
    "glados": ("Not stated: the voice is of a video game character", SHERPA),
}


def fetch(url, path):
    if not os.path.exists(path):
        subprocess.run(["/usr/bin/curl", "-sfL", "-o", path, url], check=True)
    return path


def digest_of(asset, cache):
    """Older downloads have no checksum in the release: it is made of the download."""
    path = os.path.join(cache, asset["name"] + ".sha256")
    if not os.path.exists(path):
        archive = fetch(asset["browser_download_url"], os.path.join(cache, asset["name"]))
        with open(archive, "rb") as file:
            digest = hashlib.file_digest(file, "sha256").hexdigest()
        open(path, "w").write(digest)
        os.remove(archive)
    return open(path).read().strip()


def split(name):
    """'en_US-amy-medium' as ('en_US', 'amy', 'medium')."""
    language, rest = name.split("-", 1)
    for quality in QUALITIES:
        for sep in ("-", "_"):
            if rest.endswith(sep + quality):
                return language, rest[: -len(quality) - 1], quality
    return language, rest, ""


def speaker_key(speaker):
    """'tjiho-model1' is tjiho's; 'SA_miro_V2' its own."""
    return re.sub(r"-model\d$", "", speaker)


def pretty(speaker):
    if speaker in NAMES:
        return NAMES[speaker]
    model = re.match(r"(.+)-model(\d)$", speaker)
    if model:
        return f"{pretty(model.group(1))} {model.group(2)}"
    return " ".join(part.capitalize() for part in re.split(r"[_-]", speaker))


def licence_of(card):
    if card is None:
        return None
    text = open(card, encoding="utf-8").read()
    match = re.search(r"^\s*\*?\s*License:\s*(.+)$", text, re.MULTILINE | re.IGNORECASE)
    if not match:
        return None
    return normalised(match.group(1).strip())


def normalised(value):
    """One name for each licence, however the card writes it."""
    cc = re.search(r"creativecommons\.org/licenses/([a-z-]+)/([\d.]+)", value)
    if cc:
        value = f"CC {cc.group(1).upper()} {cc.group(2)}"
    value = re.sub(r"^CC[- ]BY", "CC BY", value)
    value = re.sub(r"^CC BY-(\d)", r"CC BY \1", value)
    value = re.sub(r"^(CC BY-SA)[- ]", r"\1 ", value)
    value = re.sub(r"\s+International$", "", value)
    value = {
        "See URL": "See the dataset", "See LICENSE file": "See the dataset", "Unknown": "Not stated",
        "CC0 1.0 Universal": "CC0", "public domain": "Public domain", "mit": "MIT",
        "Apache 2.0": "Apache-2.0", "apache-2.0": "Apache-2.0", "AGPLv3": "AGPL-3.0",
        "https://www.apache.org/licenses/LICENSE-2.0.txt": "Apache-2.0",
        "http://unlicense.org": "Unlicense", "cc-by-nc-4.0": "CC BY-NC 4.0",
        "Creative Commons Attribution 4.0": "CC BY 4.0", "Attribution-ShareAlike 4.0": "CC BY-SA 4.0",
        "CC BY": "CC BY 4.0",
        "https://www.cstr.ed.ac.uk/projects/blizzard/2013/lessac_blizzard2013/license.html":
            "The Blizzard Challenge 2013 licence of the Lessac data",
        "https://www.iitm.ac.in/donlab/indictts/downloads/license.pdf": "The IndicTTS licence",
    }.get(value, value)
    if value == "Not stated":
        value = "Not stated: check the source"
    if re.search(r"\bNC\b|non-?commercial", value, re.IGNORECASE) and "non-commercial" not in value.lower():
        value += ": non-commercial"
    return value


def swift(text):
    return json.dumps(text, ensure_ascii=False)


def main(cache):
    os.makedirs(os.path.join(cache, "cards"), exist_ok=True)
    release = json.load(open(fetch(RELEASE, os.path.join(cache, "tts-models.json"))))
    voices = json.load(open(fetch(VOICES, os.path.join(cache, "voices.json"))))
    assets = sorted((a for a in release["assets"]
                     if a["name"].startswith("vits-piper-") and a["name"].endswith(".tar.bz2")
                     and "int8" not in a["name"] and "fp16" not in a["name"]), key=lambda a: a["name"])

    names = {entry["language"]["code"]: entry["language"]["name_english"] for entry in voices.values()}
    models, offered = [], []
    for asset in assets:
        name = asset["name"][len("vits-piper-"):-len(".tar.bz2")]
        language, speaker, quality = split(name)
        key = f"{language}-{speaker_key(speaker)}"
        if key not in GENDERS:
            sys.exit(f"No gender for {key}: add it to GENDERS.")
        language_id, language_name = LANGUAGES.get(language) or (language.split("_")[0], names[language])
        if name in voices:
            entry = voices[name]
            folder = f"{entry['language']['family']}/{entry['language']['code']}/{entry['name']}/{entry['quality']}"
            card = fetch(f"{HF}/resolve/main/{folder}/MODEL_CARD", os.path.join(cache, "cards", name))
            licence = licence_of(card) or "Not stated: check the source"
            source = f"{HF}/blob/main/{folder}/MODEL_CARD"
        else:
            licence, source = next((value for part, value in OTHER_LICENCES.items() if part in speaker.lower()),
                                   ("Not stated: check the source", SHERPA))
        megabytes = max(1, round(asset["size"] / 1_000_000))
        sha256 = (asset.get("digest") or digest_of(asset, cache)).removeprefix("sha256:")
        models.append((name, language_id, language_name, quality, sha256, megabytes, licence, source))
        for title, gender, sid in SPEAKERS.get(key, [(pretty(speaker), GENDERS[key], 0)]):
            offered.append([name, language_id, title, gender, sid, quality])

    # The same name in a language more than once: the qualities tell them apart.
    seen = {}
    for voice in offered:
        seen.setdefault((voice[1], voice[2]), []).append(voice)
    for same in seen.values():
        if len(same) > 1:
            for voice in same:
                voice[2] += f" ({voice[5].replace('_', '-') or 'standard'})"
    # Still the same: numbered.
    seen = {}
    for voice in offered:
        seen.setdefault((voice[1], voice[2]), []).append(voice)
    for same in seen.values():
        if len(same) > 1:
            for number, voice in enumerate(same[1:], start=2):
                voice[2] = voice[2][:-1] + f" {number})"

    print("// Generated by tools/piper_catalog.py from sherpa-onnx's tts-models release and")
    print("// Piper's voices.json: change that, not this.")
    print()
    print("extension PiperModel {")
    print("    static let all: [PiperModel] = [")
    for name, language_id, language_name, quality, sha256, megabytes, licence, source in models:
        print(f"        PiperModel(id: {swift(name)}, language: SpeechLanguage(id: {swift(language_id)}, "
              f"name: {swift(language_name)}),")
        print(f"                   quality: {swift(quality)}, sha256: {swift(sha256)}, megabytes: {megabytes},")
        print(f"                   licence: {swift(licence)}, source: {swift(source)}),")
    print("    ]")
    print("}")
    print()
    print("extension PiperVoice {")
    print("    static let all: [PiperVoice] = [")
    for name, _, title, gender, sid, _ in offered:
        print(f"        PiperVoice(model: {swift(name)}, speaker: {sid}, name: {swift(title)}, gender: .{gender}),")
    print("    ]")
    print("}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
