# GlassDock

Je Dock, met widgets. Een native Mac-app (Swift, SwiftUI en AppKit) die de macOS-Dock vervangt door een glazen Dock met live widgets naast je apps. Nagebouwd naar het idee van [Glasswave Dock](https://glasswave.app/dock).

- **Liquid Glass** op macOS 26 Tahoe, matglas op macOS 14 Sonoma en 15 Sequoia, licht en donker.
- **Apps**: je eigen Dock-apps worden bij de eerste start overgenomen. Vergroting onder de aanwijzer, stip onder geopende apps, stuiteren bij openen, recente apps. Rechtsklik voor Houd in Dock, Verberg en Stop. Sleep een app op de Dock om hem toe te voegen.
- **Downloads**: nieuwste bestanden bovenop, een voortgangsteken tijdens het downloaden en een sprongetje als hij klaar is. Klik voor een kaart per dag, met zoeken, openen en slepen.
- **Prullenmand**: sleep bestanden erop, rechtsklik om te legen.
- **Widgets**: klik voor de snelle taak, houd ingedrukt voor de kaart. Rechtsklik om toe te voegen of te verwijderen. Te veel widgets? Per set met een volgende-knop, of in een stapel.
- **Kant-en-klare Docks**: Alledaags, Developer, Productiviteit, Student, Systeemmonitor.
- De macOS-Dock wordt verborgen zolang GlassDock draait en komt terug als je stopt (ook via het menubalk-icoon: *Herstel macOS-Dock*).

## Widgets (24)

| Groep | Widgets |
| --- | --- |
| Tijd en agenda | Klok (met wereldklokken), Hierna (volgende afspraak met Neem deel), Maan, Timestamp |
| Focus | Timer, Pomodoro, Stopwatch, To-do, Notitie, Teller, Adem |
| Muziek | Speelt nu (Spotify en Apple Music, afspelen, pauze, vorige, volgende) |
| Je Mac | Batterij (lading, capaciteit, cycli, temperatuur), Activiteit (CPU, geheugen), Netwerk, Opslag, Wakker houden, Vergrendel en sluimer, Weergave (licht/donker) |
| Developer | Dev-servers (alles wat op localhost luistert, openen of stoppen) |
| Tools | Rekenmachine, Kleurkiezer, Klembord, Wachtwoord |

## Installeren

### Optie 1: kant-en-klaar downloaden
1. Ga naar **Actions → Build GlassDock** in deze repo, open de nieuwste groene run en download het artefact **GlassDock**.
2. Pak `GlassDock.zip` uit en sleep `GlassDock.app` naar **Programma's**.
3. De app is niet door Apple genotariseerd. Haal daarom eenmalig de quarantaine weg:
   ```sh
   xattr -dr com.apple.quarantine /Applications/GlassDock.app
   ```
   of open hem en kies daarna in **Systeeminstellingen → Privacy en beveiliging** voor *Open toch*.

### Optie 2: zelf bouwen
Nodig: macOS 14 of nieuwer en Xcode (of `xcode-select --install`).
```sh
git clone https://github.com/Michelvanderput/dock.git
cd dock
./scripts/build-app.sh
open build/GlassDock.app
```

## Gebruik

- Het icoon in de menubalk opent de instellingen, verbergt de Dock of zet de macOS-Dock terug.
- **Instellingen → Algemeen**: start bij inloggen, macOS-Dock verbergen.
- Sommige widgets vragen eenmalig toestemming: Agenda (Hierna), Automatisering (Speelt nu, Weergave, Prullenmand legen) en Toegankelijkheid (Vergrendel).
- Crasht de app ooit en blijft de macOS-Dock weg? Start GlassDock opnieuw en kies *Herstel macOS-Dock*, of:
  ```sh
  defaults delete com.apple.dock autohide-delay; defaults write com.apple.dock autohide -bool false; killall Dock
  ```

Geen account, geen tracking. Alleen Dev-servers kijkt naar je eigen localhost; niets gaat het internet op, behalve albumhoezen van Spotify.

GlassDock is een eigen project en niet gemaakt door of verbonden aan Glasswave of Apple.
