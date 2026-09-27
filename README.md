---
title: Afaan Oromo Integrated Speech Technology
emoji: 🎙️
colorFrom: blue
colorTo: purple
sdk: docker
pinned: false
license: mit
---

# 🎙️ Development of an Integrated Speech Technology System for Afaan Oromo

<p align="center">
  <img src="https://img.shields.io/badge/Language-Afaan%20Oromoo-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/ASR%20WER-1.5%25-brightgreen?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/TTS%20MOS-4.35%2F5.0-gold?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Corpus-101%2C518%20pairs-orange?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/License-Open%20Access-green?style=for-the-badge"/>
</p>

> **Bachelor of Science Thesis** — Hawassa University, Hawassa Institute of Technology
> Department of Electrical and Computer Engineering · Computer Engineering Stream
> **Authors**: Admassu Ashebir · Hunde Dejene · Nimona Asefa
> **Advisor**: Mr. Musa Hayato (MSc) · **Submitted**: May 2026 · Hawassa, Ethiopia

---

## 📄 Read the Paper

| Format | Link |
|--------|------|
| 📥 **Full Thesis PDF** | [Download PDF](https://github.com/HD-CMP/afaan-oromo-speech-system/blob/main/paper/Afaan_Oromoo_Speech_Thesis_Final.pdf) |
| 🤗 **Live Demo** | [Hugging Face Space](https://huggingface.co/spaces/HNDE/afaan-oromo-stt-api) |
| 📱 **Mobile App APK** | [Download APK](https://github.com/HD-CMP/afaan-oromo-speech-system/releases) |

---

## 🌍 Why Afaan Oromoo?

Afaan Oromoo (also written Afaan Oromo) is a **Cushitic language** spoken by over **50 million people** in Ethiopia and the Horn of Africa — making it one of the most widely spoken languages on the continent. Despite this, it remains critically **underrepresented in speech technology**:

- No production-ready Text-to-Speech (TTS) system existed
- Existing ASR systems were fragmented and had high error rates
- No unified speech platform integrated ASR + TTS + OCR together
- Speakers could not interact with technology in their native language

This thesis directly addresses this gap by building a **complete, end-to-end integrated speech technology system** covering ASR, TTS, and OCR, deployed as both a live API and a cross-platform mobile application.

---

## 🔬 Research Overview

### Problem Statement
While Automatic Speech Recognition (ASR) for Afaan Oromoo had seen some progress, the **absence of Text-to-Speech (TTS)** synthesis left existing systems fundamentally unidirectional — users could speak to machines but machines could not speak back. Additionally, no system combined ASR + TTS + OCR into a unified platform accessible to everyday users.

### Approach
This thesis takes a **comparative empirical approach** — testing multiple state-of-the-art neural architectures across controlled experimental configurations to identify the best performing system under low-resource and GPU-constrained conditions (Kaggle T4 GPU).

---

## 🧠 System Architecture

The system consists of **three core components** integrated into a unified platform:

```
┌─────────────────────────────────────────────────────┐
│           Integrated Speech Technology               │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐  │
│  │     ASR      │  │     TTS      │  │    OCR    │  │
│  │  (Whisper)   │  │ (Fish Speech │  │ (ML Kit)  │  │
│  │  WER: 1.5%   │  │  + LoRA)     │  │ On-device │  │
│  │              │  │  MOS: 4.35   │  │           │  │
│  └──────┬───────┘  └──────┬───────┘  └─────┬─────┘  │
│         └─────────────────┼────────────────┘        │
│                           ▼                          │
│              ┌─────────────────────┐                 │
│              │   FastAPI Backend   │                 │
│              │  (HuggingFace API)  │                 │
│              └──────────┬──────────┘                 │
│                         ▼                            │
│          ┌──────────────────────────┐                │
│          │  Flutter Mobile App      │                │
│          │  (Android · iOS · Web)   │                │
│          └──────────────────────────┘                │
└─────────────────────────────────────────────────────┘
```

---

## 🗣️ Component 1 — Automatic Speech Recognition (ASR)

**Model**: OpenAI Whisper-Small fine-tuned on Afaan Oromoo

| Detail | Value |
|--------|-------|
| Base model | `openai/whisper-small` |
| Fine-tuning corpus | 101,518 audio–text pairs (~141 hours) |
| Training method | Progressive fine-tuning on Kaggle T4 GPU |
| Final WER | **1.5%** on validation set |
| HF Model | `HNDE/afaan-oromo-whisper-small` |

**Features implemented:**
- Real-time speech-to-text transcription
- Subtitle generation with timestamps (SRT format)
- Live streaming transcription via WebSocket
- Batch audio file processing

**Corpus Construction:**
The training corpus was assembled from multiple sources including studio recordings, public speech datasets, and synthetically augmented data, expanding from an initial smaller set to **101,518 pairs (~141 hours)** through iterative data collection. Progressive fine-tuning was used — starting with a smaller, cleaner subset and expanding to the full corpus as model quality improved.

---

## 🔊 Component 2 — Text-to-Speech Synthesis (TTS)

**Comparative evaluation of 3 neural TTS architectures across 10 configurations:**

### Architecture Comparison

| Architecture | Approach | Result |
|---|---|---|
| **F5-TTS** | Flow-matching diffusion | ❌ Failed — strong English/Mandarin phonetic priors prevented adaptation |
| **VITS** (unfrozen) | Variational inference + adversarial | ❌ Collapsed — GAN training instability caused artifacts |
| **VITS** (frozen decoder) | Partial fine-tuning | ⚠️ Moderate — limited expressiveness |
| **Fish Speech + LoRA** | Codec-based LM + Low-Rank Adaptation | ✅ **Best — MOS 4.35/5.0** |
| **Fish Speech + LoRA + RVC v2** | + Retrieval-based Voice Conversion | ✅ **Best overall naturalness** |

### Key Finding
> **Architecture selection is more consequential than dataset scale for low-resource TTS.**
> Fish Speech fine-tuned via LoRA (r=32) combined with RVC v2 achieves the highest naturalness and intelligibility.

### TTS Evaluation

| Metric | Value |
|--------|-------|
| Mean Opinion Score (MOS) | **4.35 / 5.0** |
| Evaluators | 10 native Afaan Oromoo speakers |
| Best architecture | Fish Speech + LoRA r=32 + RVC v2 |
| Training platform | Kaggle T4 GPU |

---

## 📷 Component 3 — Optical Character Recognition (OCR)

**Technology**: Google ML Kit (on-device)

- Fully **on-device processing** — no network call needed
- Reads Afaan Oromoo text from images and camera
- Feeds recognized text directly into the TTS engine (text → speech from image)
- Supports the **"Read to Me"** workflow: photograph a document → hear it read aloud in Afaan Oromoo

---

## 📱 Mobile Application

A cross-platform **Flutter mobile application** integrates all three components:

| Screen | Functionality |
|--------|--------------|
| 🎤 **ASR / Transcription** | Record speech → get Afaan Oromoo text transcript |
| 📝 **Subtitles** | Upload audio/video → generate timestamped SRT subtitles |
| 🔊 **TTS** | Type or paste Afaan Oromoo text → hear it spoken |
| 📷 **OCR → TTS** | Photograph text → read it aloud |
| 📖 **Research** | View thesis, citations, results, access paper PDF |
| 🕐 **History** | All transcriptions and generations saved locally |

**Platform support**: Android (primary), iOS, Web

---

## 🚀 Deployment

The system is deployed across **4 Hugging Face Spaces**:

| Space | Purpose |
|-------|---------|
| `HNDE/afaan-oromo-stt-api` | Main FastAPI backend (ASR + TTS + subtitles) |
| `HNDE/afaan-oromo-whisper-small` | ASR model repository |
| Additional spaces | TTS demo · Web interface |

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/transcribe` | POST | Audio file → Afaan Oromoo text |
| `/generate-subtitles` | POST | Audio → SRT subtitle file |
| `/tts` | POST | Text → speech audio |
| `/ws/transcribe` | WebSocket | Live streaming transcription |
| `/health` | GET | API health check |

---

## 📊 Key Results Summary

| Metric | Result | Details |
|--------|--------|---------|
| ASR Word Error Rate | **1.5%** | Whisper-Small on 101,518-pair corpus |
| TTS Mean Opinion Score | **4.35 / 5.0** | Fish Speech + LoRA r=32 + RVC v2 |
| Training Corpus | **101,518 pairs** | ~141 hours of Afaan Oromoo speech |
| Best TTS Model | **Fish Speech + LoRA** | Outperformed F5-TTS and VITS |
| OCR | **On-device** | Google ML Kit, no network required |
| Deployment | **4 HF Spaces** | Live API + web demos |
| Mobile App | **Flutter** | Android · iOS · Web |

---

## 🗝️ Keywords

`Afaan Oromoo` · `Low-Resource Language` · `Automatic Speech Recognition` · `Text-to-Speech` · `Whisper` · `Fish Speech` · `VITS` · `F5-TTS` · `Low-Rank Adaptation (LoRA)` · `Retrieval-based Voice Conversion (RVC)` · `Cushitic Languages` · `Ethiopian NLP` · `Flutter` · `FastAPI` · `HuggingFace`

---

## 📖 Citation

**APA:**
> Ashebir, A., Dejene, H., & Asefa, N. (2026). *Development of an Integrated Speech Technology System for Afaan Oromo* [Bachelor's thesis]. Hawassa University, Hawassa Institute of Technology.

**BibTeX:**
```bibtex
@thesis{ashebir2026afaan,
  title     = {Development of an Integrated Speech Technology System for Afaan Oromo},
  author    = {Ashebir, Admassu and Dejene, Hunde and Asefa, Nimona},
  year      = {2026},
  month     = {May},
  school    = {Hawassa University, Hawassa Institute of Technology},
  address   = {Hawassa, Ethiopia},
  type      = {Bachelor's Thesis},
  department= {Department of Electrical and Computer Engineering}
}
```

---

## 👥 Authors & Acknowledgements

| Role | Name |
|------|------|
| Author | Admassu Ashebir |
| Author | Hunde Dejene |
| Author | Nimona Asefa |
| Advisor | Mr. Musa Hayato (MSc) |
| Institution | Hawassa University — Hawassa Institute of Technology |
| Location | Hawassa, Ethiopia |

---

<p align="center">
  Made with ❤️ for Afaan Oromoo speakers worldwide · Hawassa University 2026
</p>
