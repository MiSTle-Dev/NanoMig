# Zusammenarbeit NanoMig — Rudi7503 ↔ toby01019

Stand 2026-10-31. Diese Datei regelt den technischen Austausch zwischen beiden
Seiten. Sie ersetzt keine Fakten: was gilt, steht im Code und in den Belegen.

## Rollen

| Seite | Beitrag |
|---|---|
| **Rudi (Rudi7503)** | Core-Entwicklung, RTL, Constraints, Build, Freigabe von Releases |
| **Toby (toby01019)** | Hardware-Tests auf dem MiSTer, Testprogramme, Hörtests, Befundpackages |

Die KI-Assistenten beider Seiten arbeiten im Auftrag. Sie dürfen Vorschläge
machen und Befunde erheben, aber nichts als geprüft bezeichnen, was nicht
belegt ist (siehe *Belegpflicht*).

## Ein einziges Integrationsziel

`Rudi7503/NanoMig`, Branch **`feature/16ch-audio-biquad-pipeline`**.

* Basis dieses Branches: `6ea514e` (Upstream-Stand vom 2026-10-26), darauf 15 Commits.
* `main` ist reiner Upstream-Spiegel von `MiSTle-Dev/NanoMig` und wird nicht direkt bearbeitet.
* **Achtung:** Upstream ist inzwischen 20 Commits weiter. Ein Rebase auf den
  aktuellen Upstream ist ein eigener Vorgang und macht jede darauf gebaute
  RBF ungültig — nur mit separater Absprache.

## Branches und Pull Requests

* `rudi/<thema>` — Core, RTL, Doku
* `toby/<thema>` — Testprogramme, Hardware-Befunde, Belege
* PRs immer gegen `feature/16ch-audio-biquad-pipeline`, nie gegen `main`.
* Kein Force-Push auf den Integrationsbranch. Jeder rebased nur seinen eigenen Themenbranch.
* **Ein PR = ein Thema.** RTL-Fix, Doku-Korrektur und Pfadanpassungen nicht mischen.
* Der PR nennt den Basis-Commit, auf dem er aufsetzt.

## Wer ändert was (ohne Rückfrage)

| Bereich | Owner | Dateien |
|---|---|---|
| Audio-RTL | Rudi | `mister/rtl/audio_ext/*`, `mister/rtl/audio_ext.v` |
| Capture-RTL | Rudi | `mister/rtl/audio_capture.v`, `mister/rtl/audio_ext/audio_capture.v` |
| SySTEM/Build | Rudi | `mister/sys/*`, `mister/Minimig.qsf`, `mister/files.qip` |
| Testprogramme | Toby | `mister/tests/*` |
| Hardware-Belege | Toby | `mister/verify/<datum>-<thema>/` |
| Doku | beide, PR-pflichtig | `README.md`, `GITHUB_AI_HANDOVER.md`, `COLLABORATION.md` |

Alles andere: vorher im PR-Thread abstimmen.

## Belegpflicht — Definition of Done

Jeder PR beantwortet vier Fragen, sonst wird er nicht gemergt:

1. **Was ist geändert** und auf welchem Basis-Commit?
2. **Was ist geprüft** — und womit (Simulationslog, Synthese, Timing, Hardware)?
3. **Was ist ausdrücklich nicht geprüft?** „Nicht geprüft" ist ein gültiges
   Ergebnis und muss dastehen; es wird nicht weggelassen.
4. **Was kostet es** — Ressourcen, Timing, Verhalten im Wiedergabepfad?

Belege sind Dateien im PR (Log, Rohdaten, Hash), keine Prosa. Ein
Synthese-Erfolg ist kein Timing-Pass. Eine Hörprobe ist kein Sample-Beweis.

## Umgang mit gelieferten Patches

* Patches werden gegen den genannten Basis-Commit geprüft, nicht gegen den
  eigenen Arbeitsstand.
* Pfad- und Umgebungskorrekturen gehören nicht in den Patch, sondern in die
  Bauanleitung; sonst ist der Patch nicht reproduzierbar.
* Weicht ein gelieferter Kandidat von der gemergten Datei ab, wird die
  Abweichung benannt — auch wenn sie nur Kommentare betrifft.
* Byte-Identität zwischen getestetem Kandidaten und gemergter Datei ist das Ziel.

## Offene Entscheidungen

| Thema | Stand | Klärung durch |
|---|---|---|
| DMA-Länge: `AUDxLEN` in Worten oder Bytes? | Doku sagt Worte, der 16CH-Test rechnet mit 256 Bytes | Rudi bestätigt gegen RTL-Zähler |
| Audio-Registerbasis: `$DFF400` oder `$DFF800`? | Handover sagt `$DFF400`, `mister/README.md` sagt `$DFF800` | Rudi, dann Doku-Fix |
| Doppelte RTL-Kopien (`rtl/x.v` und `rtl/x/x.v`) | identisch, nur `rtl/audio_ext/...` wird gebaut | Rudi, Aufräum-PR |
| Timing `feature`-Branch: −1,819 ns | offen, unverändert | Rudi |
| Upstream-Rebase (20 Commits Rückstand) | bewusst zurückgestellt | beide |

## Technische Randbedingungen

* Quartus Prime Lite 25.1std, Gerät `5CSEBA6U23I7`, Projekt `Minimig`, Top `sys_top`.
* Simulation: Icarus Verilog `-g2012`. Toolpfade gehören in eine Umgebungsvariable,
  nicht fest in ein Skript.
* Rohdaten aus der Capture-Einheit: **Big-Endian** int16, stereo verschränkt.
  Wer das anders liest, bekommt Plausibles, aber Falsches.
* Jede RBF wird mit SHA256 und dem exakten Quellstand ausgeliefert.
