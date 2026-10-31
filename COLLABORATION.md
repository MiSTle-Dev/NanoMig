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

`Rudi7503/NanoMig`, Branch **`main`**. Dort wird gemeinsam gearbeitet.

* `main` ist Integration **und** Upstream-Ableger: 20 Upstream-Commits vom
  2026-10-30 plus die 15 Audio-Commits, zusammengeführt als Merge `aacf921`.
* Bewusst **gemergt, nicht rebased**: die Commit-Hashes `d90e0fb`, `0b86a3e`
  und `3fba796` bleiben gültig. Tobys Befundpackages verweisen darauf.
* `feature/16ch-audio-biquad-pipeline` ist **eingefroren**, nur noch Referenz.
  Nicht weiter darauf arbeiten und nicht löschen, solange eine RBF im Umlauf ist,
  die darauf gebaut wurde.
* Upstream (`MiSTle-Dev/NanoMig`) läuft weiter. Aktualisierung nur als bewusster
  Merge `origin/main` → `main`, nie als Rebase und nie während ein Hardware-Test
  gegen einen bestimmten Stand läuft.

### Warum der Wechsel unkritisch war

Die 20 Upstream-Commits berühren ausschließlich `NETWORKING.md`,
`nanomig-uart-fifo.patch`, `src/misc/amiga.xml`, `src/misc/uart_port.v` und
`src/scripts/build.tcl` — nichts davon liegt im MiSTer-Baum `mister/`.
Der einzige gemeinsam geänderte Pfad war `src/misc/amiga.xml`, dort aber
verschiedene Stellen; der Merge lief konfliktfrei durch.

## Branches und Pull Requests

* `rudi/<thema>` — Core, RTL, Doku
* `toby/<thema>` — Testprogramme, Hardware-Befunde, Belege
* `main` ist gemeinsamer Arbeitsbranch: **direktes Pushen ist erlaubt.**
  Gesperrt ist nur der Force-Push, per Ruleset `no-force-push` — für beide Seiten
  und ohne Bypass. Grund: Commits werden in Befundpackages per Hash zitiert, und
  jede RBF hängt an einem Quellstand; ein Force-Push macht beides unauffindbar.
* Für RTL-Änderungen und alles, was eine RBF beeinflusst, ist ein PR der
  vereinbarte Weg — nicht als Kontrolle, sondern weil der PR der Ort ist, an dem
  „geprüft / nicht geprüft" dokumentiert wird. Doku-Korrekturen und Kleinkram
  dürfen direkt gepusht werden.
* Jeder rebased nur seinen eigenen Themenbranch.
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
| Upstream-Abgleich | erledigt am 2026-10-31 (Merge `aacf921`), ab jetzt periodisch | beide |
| Capture-Stereo-Fix | liegt als `rudi/capture-stereo-coherence` (`225e8d5`) bereit | Rudi → PR |

## Technische Randbedingungen

* Quartus Prime Lite 25.1std, Gerät `5CSEBA6U23I7`, Projekt `Minimig`, Top `sys_top`.
* Simulation: Icarus Verilog `-g2012`. Toolpfade gehören in eine Umgebungsvariable,
  nicht fest in ein Skript.
* Rohdaten aus der Capture-Einheit: **Big-Endian** int16, stereo verschränkt.
  Wer das anders liest, bekommt Plausibles, aber Falsches.
* Jede RBF wird mit SHA256 und dem exakten Quellstand ausgeliefert.
