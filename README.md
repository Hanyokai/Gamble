# Gamble

Version 0.18.2

## Handel für offene Zahlungen (0.17.4)

Die vorhandenen Einsatz- und Gewinnerfenster sowie die DoN-Ansicht bieten „Handel mit <Name>“. `TradeAction.lua` bereitet einen SecureActionButton mit dem aktuellen Party-/Raid-UnitToken vor. GUIDs haben Vorrang, Namen müssen eindeutig sein. Offline-Spieler, fehlende Gruppenmitglieder und erledigte Zahlungen erhalten keine Handelsaktion. Im Kampf werden Secure-Änderungen zurückgestellt; nach Kampfende ist ein neuer Benutzerklick erforderlich. Goldbetrag und Annahme bleiben manuell. Die vorhandene Handelsbestätigung führt weiterhin die Abrechnung durch.

Ingame prüfen: Bank/Spieler in Party und Raid; normale Wette und DoN beenden; Handelsbutton beim Zahler klicken; korrektes Ziel und Handelsfenster prüfen; Gold manuell zahlen. Zusätzlich Raid-Slots tauschen, Partner entfernen/offline setzen, Zahlung im Kampf erzeugen und bereits erledigte Zahlung erneut ansehen. Forever Beta verwendet einen eigenen Client (Camelot Interface 16001); die tatsächliche Zulassung von Secure-Makro `/trade` muss dort geprüft werden. Bei Blockierung nennt die Meldung den manuellen Weg über das Zielporträt.

## Bank Security, Reserve & Solvency (0.17.0)

`BankSecurity.lua` führt die Bankbuchhaltung getrennt von der Wettlogik. Das System unterscheidet freie Bankreserve, aktive Pots, offene Auszahlungen, Refunds und reserviertes Risikokapital. `Required Reserve` zählt freie Bankreserve, aktive Pots sowie offene Payout- und Refund-Verpflichtungen jeweils genau einmal; Risikoreserven sind eine Zweckbindung innerhalb der freien Bankreserve und werden deshalb nicht nochmals addiert.

Der Bank-Button im Hauptfenster öffnet die Übersicht mit tatsächlichem Gold, privat verfügbarem Gold, Reserveklassen, Deckungsquote und Solvenzstatus. Bei Unterdeckung werden neue Wetten und neue Einzahlungen gesperrt, bestehende Auszahlungen und Rückerstattungen bleiben bestehen. Gold wird niemals technisch gesperrt; das System ist ausschließlich eine buchhalterische Schutz- und Warnschicht.

Das persistente Ledger verwendet eindeutige Transaktions-IDs, Sequenznummern, eine einfache deterministische Prüfkette und Snapshots nach jeweils 100 Transaktionen. Gruppenmitglieder mit dem Addon speichern ereignisbasiert kompakte Backup-Einträge. `RECOVER BANK DATA` fordert ausschließlich fehlende Sequenzen an. Widersprüchliche Quellen führen zu `RECOVERY CONFLICT`; eine einzige Quelle nach vollständigem lokalen Datenverlust führt konservativ zu `RECOVERY REVIEW` statt zu einer stillen Übernahme.

## Neue Encounter-Wetten (0.16.0)

- **Boss HP Wipe:** Tippe auf den Restleben-Bereich des Bosses beim Wipe. Bei einem Boss-Kill wird die Wette ungültig und vollständig zurückgezahlt. Ein HP-Wert gilt höchstens drei Sekunden lang als zuverlässig; ältere oder fehlende Werte führen zu `AMBIGUOUS` ohne automatische Auszahlung.
- **Pull Timer Death:** Tippe auf den Zeitpunkt des ersten echten Spielertodes ab `ENCOUNTER_START`. Ein erfolgreicher Boss-Kill ohne Tod ergibt `NO DEATH`; ein Wipe ohne erkannten Tod ist `AMBIGUOUS`.
- **Total Deaths:** Tippe auf die gesamte Zahl echter Spielertode bis `ENCOUNTER_END`. Wiederholte Tode nach einem Battle-Rez zählen erneut.

Die drei Modi verwenden den gemeinsamen `EncounterTracker`. Er nutzt in WoW Forever die vorhandenen Encounter-, Einheiten- und `UNIT_DIED`-Ereignisse; der zuvor problematische globale Retail-Combat-Log-Listener wird nicht verwendet. Gewinner teilen den tatsächlich eingezahlten Pot gleichmäßig. Nicht teilbare Kupferreste gehen deterministisch in alphabetischer Reihenfolge an die ersten Gewinner. Gibt es keinen richtigen Tipp, werden alle Einsätze zurückgezahlt.

Bei `AMBIGUOUS` wird keine Zahlung erzeugt. Der Host kann nach eigener Prüfung in der Optionsliste eine Gewinnoption auswählen und das Ergebnis ausdrücklich bestätigen. Im echten Forever-Client müssen insbesondere die Signaturen von `UNIT_DIED`, die Verfügbarkeit der `boss1`-Einheit sowie die Aktualität von `UNIT_HEALTH`/`UNIT_MAXHEALTH` während Encounter-Enden geprüft werden.

## Double or Nothing

**Double or Nothing** ist als vollständige Wettart in das Auswahlmenü des Gamble-
Hauptfensters integriert. Erstellung, Lobby, laufende Runden und Ergebnis werden in den
Reitern **Neue Wette** und **Laufende Wetten** angezeigt. Die Bank legt einen identischen
Einsatz fest. Teilnehmer treten der Lobby bei, handeln den
Einsatz manuell an die Bank und markieren sich als bereit. Erst wenn mindestens zwei
Spieler online, bereit und als `PAID` bestätigt sind, kann die Bank das Spiel starten.

Jeder aktive Spieler löst seinen eigenen WoW-Wurf über **WÜRFELN** aus. Ausgewertet wird
ausschließlich das von `RandomRoll(1, 100)` erzeugte Ergebnis aus `CHAT_MSG_SYSTEM`:
1–50 bedeutet OUT, 51–100 bedeutet SAFE. Sind alle Spieler einer Runde OUT, wird dieselbe
Runde ohne Pot-Änderung wiederholt. Der letzte aktive Spieler gewinnt den tatsächlich
eingezahlten Pot. Ein Spiel bleibt bis zur bestätigten manuellen Auszahlung offen.

Die Lobby, Zahlungen, Runden, Würfe, Historie und offene Auszahlung werden in
`GambleDONDB` gespeichert.

Ein WoW:-Forever-Addon fuer die Gruppenwette **„Wer stirbt beim naechsten Pull zuerst?“**

## Installation

Den kompletten Ordner `Gamble` nach
`World of Warcraft/_classic_beta_/Interface/AddOns/` kopieren und das Spiel neu starten.

## Ablauf

1. `/gamble` oeffnet die Wettlobby.
2. Oben nach einer Wettart suchen und sie im Dropdown auswaehlen.
3. Ein Gruppenmitglied auswaehlen und Gold/Silber/Kupfer eintragen.
4. **Wette eroeffnen**. Der Betrag ist zugleich der Mindesteinsatz.
5. Andere Addon-Nutzer waehlen ihren Tipp und setzen mindestens diesen Betrag.
6. Beim Pull bzw. beim passenden Bosskampf wird die Annahme automatisch geschlossen.
7. Das erste vom Spiel gemeldete `UNIT_DIED` eines anwesenden Gruppenmitglieds entscheidet die Wette.

## Wettarten

- **Naechster Pull:** Der naechste Kampf des Spielers schliesst die Einsaetze.
- **Naechster Boss:** In Dungeon oder Raid wird der naechste `ENCOUNTER_START` verwendet.
  Ist beim Eroeffnen ein vom Client erkannter Boss anvisiert, wartet Gamble gezielt auf
  diesen Boss. Endet der Bosskampf ohne Gruppentod, wird die Wette annulliert und erstattet.

Der Pot wird proportional zu den Einsaetzen aller richtigen Tipps verteilt. Tippt niemand
richtig, werden alle Einsaetze erstattet.

## Fairer Pot / Treuhand

Der Ersteller der Wette verwaltet den Pot. Klickt ein anderer Spieler auf
**Teilnehmen & Einsatz traden**, oeffnet Gamble den Handel mit dem Ersteller und setzt den
gewaehlten Einsatz ein, soweit der Client dies erlaubt. Der Tipp wird erst aktiviert, wenn
der Handel erfolgreich abgeschlossen und der korrekte Geldeingang erkannt wurde. Der
Ersteller zahlt nach dem Ergebnis alle Gewinne bzw. Rueckerstattungen aus.

WoW erlaubt Addons nicht, einen Handel ohne Spieleraktion anzunehmen. Beide Seiten muessen
den Betrag deshalb im Handelsfenster pruefen und den Handel selbst bestaetigen.

## Befehle

- `/gamble` oder `/gamble show` – Fenster zeigen
- `/gamble hide` – Fenster ausblenden
- `/gamble status` – aktuellen Stand in den Chat schreiben
- `/gamble pay` – naechste ausstehende Zahlung vorbereiten
- `/gamble paid` – die angezeigte Zahlung nach erfolgreichem Handel als erledigt markieren
- `/gamble cancel` – offene Wette abbrechen (nur Ersteller, vor dem Pull)
- `/gamble reset` – lokale abgeschlossene Anzeige leeren

## Technische Grenzen

WoW: Forever schuetzt Live-Kampfdaten. Gamble verwendet daher das dafuer vorgesehene
`UNIT_DIED`-Ereignis statt den gesperrten Combat Log. `C_DamageMeter` wird zur Erkennung
einer laufenden/abgelaufenen Forever-Kampfsitzung abgefragt, aber geheime Meterwerte
werden weder gelesen noch verglichen. Automatisches Bestaetigen eines Goldhandels ist
von WoW absichtlich gesperrt.

Seit 0.3.1 wird die in Forever geschuetzte GUID aus `UNIT_DIED` niemals als Tabellenindex
verwendet. Der erste Tod wird secret-sicher ueber feste Gruppen-/Raid-Unit-Tokens aufgeloest.

Seit 0.3.2 verwendet die Anzeige WoWs Muenzsymbole. Sichtbare Spielernamen werden ohne
Realm-Zusatz dargestellt; fuer Synchronisierung und Handel bleibt intern der volle Name erhalten.

Seit 0.4.0 bietet die Bosswette eine optionale Bossliste aus dem Encounter Journal der
aktuellen Instanz. Standard bleibt die automatische Erkennung. Beim Start des Bosskampfs
werden nur verbundene, in derselben Instanz sichtbare Gruppenmitglieder als moegliche Tote
beruecksichtigt. Auszahlungen erscheinen ausschliesslich bei der Bank und oeffnen per Button
den Handel mit dem naechsten Gewinner inklusive vorbereitetem Betrag.

Seit 0.4.1 ergaenzt eine lokale Forever-Fallbackdatenbank fehlende Journal-Eintraege.
Enthalten ist zunaechst Ruins of Lordaeron mit den sieben derzeit im Forever-Client
bekannten Begegnungen. The Butcher und The Baron werden als dieselbe Begegnung erkannt.

Seit 0.5.0 kann die Bank eine noch nicht gestartete Wette abbrechen. Ohne fremde Einsaetze
geschieht dies sofort. Mit Teilnehmern muessen alle per Dialog zustimmen; danach werden ihre
vollstaendigen Einsaetze in die Rueckzahlungsliste der Bank aufgenommen. Lehnt eine Person
ab oder beginnt der Pull waehrend der Abstimmung, bleibt die Wette bestehen.

Seit 0.6.0 gibt es die Wettart **Boss-Serie**. Jeder Teilnehmer tippt fuer jeden Boss der
Instanz den ersten Toten und zahlt einen Einsatz fuer die ganze Serie. Pro Boss ohne richtigen
Tipp behaelt die Bank 20 Prozent des rechnerisch gleich grossen Bossanteils; die restlichen
80 Prozent bleiben im finalen Pot. Am Ende gewinnt die hoechste Anzahl richtiger Tipps,
bei Gleichstand wird proportional zu den Einsaetzen geteilt. Die Bank kann optionale oder
ausgelassene Bosse mit **Serie abschliessen** beziehungsweise `/gamble finish` beenden.
Nach jeder abgeschlossenen Einzelwette fuehrt **Zur Wettlobby** direkt zur Auswahl zurueck.

Seit 0.6.1 besitzt die Boss-Serie einen Assistenten mit **Zurueck** und **Weiter**. Eine
komplette Tippuebersicht markiert den aktuell bearbeiteten Boss und noch offene Tipps.
Fruehere Angaben lassen sich bis zum Start der Serie beliebig ersetzen; der Startbutton
wird erst freigeschaltet, wenn fuer jeden Boss ein Tipp vorhanden ist.

Seit 0.6.2 ist jede Zeile der Boss-Tippuebersicht direkt anklickbar. Sowohl bereits
gewaehlte, klassenfarbig dargestellte Spielernamen als auch **noch offen** springen sofort
zum jeweiligen Boss, damit Tipps ohne Umweg ueber Zurueck/Weiter geprueft werden koennen.

Seit 0.7.0 gibt es die Wettart **Item-Drop**. Nach Auswahl eines Bosses liest Gamble dessen
Beuteliste aus dem Encounter Journal. Jedes Item kann innerhalb einer Wette nur von einer
Person belegt werden. Bossbeute wird ueber Lootfenster und Beutechat erkannt. Gibt es keinen
Treffer, behaelt die Bank 20 Prozent; die restlichen 80 Prozent werden als bossbezogener
Jackpot fuer die naechste Item-Drop-Wette gespeichert. Bei einem Treffer wird dieser Jackpot
zusammen mit dem neuen Pot ausgezahlt, waehrend fruehere Bankanteile unberuehrt bleiben.

Seit 0.7.1 enthaelt die lokale Forever-Datenbank auch die bekannten Beutelisten samt echter
Item-IDs fuer alle Begegnungen in Ruins of Lordaeron. Sie werden automatisch verwendet,
wenn der Forever-Client fuer einen Fallback-Boss keine Encounter-Journal-ID bereitstellt.

Seit 0.7.2 fragt Gamble Itemlinks und Symbole versionssicher ab. Clients ohne die globale
`GetItemInfo`-Funktion verwenden die entsprechende `C_Item`-Variante; fehlen beide APIs,
bleiben die eingebauten Itemnamen und IDs trotzdem voll nutzbar.

Seit 0.7.3 zeigt die Tippauswahl fuer **Naechster Boss** und **Boss-Serie** immer alle
Mitglieder der Gruppe beziehungsweise des Raids. Fuer die Wertung zaehlen weiterhin nur
Spieler, die beim Start des jeweiligen Bosskampfs verbunden und vor Ort sichtbar sind.
Bei einer Boss-Serie wird diese Anwesenheitsliste vor jedem einzelnen Boss neu erstellt.

Seit 0.11.0 koennen beliebig viele Wetten gleichzeitig laufen. Das gilt auch fuer mehrere
Wetten derselben Wettart. Jede Wette besitzt eine eigene ID, wird separat synchronisiert
und in der Ansicht "Laufende Wetten" als eigene Karte angezeigt.

Seit 0.8.1 bleibt die Wettart einer bereits eroeffneten Wette fest eingestellt. Dadurch
loescht ein versehentlicher Klick im Wettartmenue keine Boss-Serientipps mehr. Einzelne
Tipps der Serie koennen weiterhin geaendert werden; eine leere lokale Anzeige wird aus dem
bereits gespeicherten eigenen Einsatz automatisch wiederhergestellt.

Seit 0.8.2 vergleicht Gamble den eingegebenen Einsatz laufend mit dem verfuegbaren Geld
des Spielers. Unterhalb des Mindesteinsatzes oder oberhalb des eigenen Vermoegens bleibt
der Teilnahmebutton deaktiviert. Vor dem Handelsstart wird derselbe Betrag erneut geprueft.

Seit 0.8.3 besitzt Gamble einen verschiebbaren Minimap-Button mit Muenzsymbol. Ein Klick
oeffnet oder schliesst das Wettbuero; durch Ziehen laesst sich das Symbol um die Minimap
bewegen. Die Position wird in den gespeicherten Addondaten beibehalten.

Seit 0.8.4 ueberstehen laufende Wetten, Tipps, Einsaetze, Ergebnisse und offene Zahlungen
ein `/reload`. Ein geoeffnetes Handelsfenster wird aus Sicherheitsgruenden nicht automatisch
fortgesetzt; die zugehoerige Wette beziehungsweise Zahlung bleibt jedoch gespeichert.

Seit 0.8.5 werden Serientipps beim Start des jeweiligen Bosskampfs festgeschrieben. Bereits
gestartete oder gewertete Bosse sind als gesperrt markiert; nur spaetere, noch nicht gestartete
Bosse lassen sich anpassen. Ein bestaetigter Serieneinsatz kann nur erhoeht werden. Bei einer
Erhoehung wird ausschliesslich die Differenz zur bisherigen Einzahlung gehandelt.

Seit 0.8.6 sitzt der Minimap-Button standardmaessig weiter aussen. Mit
`/gamble minimap 94` kann sein Abstand und mit `/gamble minimap 94 225` zusaetzlich sein
Winkel numerisch festgelegt werden. Erlaubt sind Abstaende von 55 bis 140 Pixeln.

Seit 0.9.0 liegen Forever-spezifische Instanz-, Boss- und Lootdaten getrennt in
`Gamble_Data.lua`. Vollstaendige lokale Lootlisten sind fuer Hall of Thanes und Ruins of
Lordaeron enthalten. Fuer Excavation Site: Wetlands und City of Dalaran sind die derzeit
oeffentlich bekannten Bosse eingetragen; deren Drops sowie die Daten der fuenf spaeteren
Forever-Instanzen werden ergaenzt, sobald verlaessliche Item-IDs bekannt sind. Klassische
Instanzen und Raids werden weiterhin primaer aus dem Encounter Journal des Clients geladen.

Seit 0.9.1 enthaelt `Gamble_ClassicData.lua` zusaetzlich eine vollstaendige lokale Vanilla-
Bossdatenbank fuer alle klassischen Dungeons und Level-60-Raids mit mehr als 300 Boss- und
Sonderbegegnungen sowie deren Item-IDs. Dadurch bleibt die Auswahl auch auf Forever-Clients
ohne klassische Encounter-Journal-Daten verfuegbar. Die Vanilla-Grunddaten wurden aus dem
GPL-2.0-Projekt AtlasLootClassic uebernommen und in Gambles kompaktes Format konvertiert.
## Top-3 Damage Bets (0.18.0)

In Boss Damage Series, targeting any listed, unscored boss from any group member opens a synchronized Top-3 popup. Paid participants can revise that boss's tip until the pull, including during an already-running series. Complete tips are sent to and acknowledged by the host; late requests are rejected. The boss locks at combat/encounter start and remains locked after a wipe. Repeated targeting of the same boss does not repeatedly open the window. Public target names are required; protected values are never inspected. Both clients need 0.18.2 for this popup workflow.

Damage Race tips places 1–3 (places 1–2 for a two-player roster), with no duplicate player in a tip. Select a place button, then a player. Each exact place gives one point. The best score wins; tied bettors split the entire paid pot in proportion to stakes. Zero correct places or unreadable data refunds all stakes. Equal damage shares competition ranks, e.g. 1, 1, 3. The host sends scores and payouts authoritatively.

`DamageRaceBets.lua` also adds **Boss Damage Series: Top 3**, using the existing remaining-boss list. Tips are entered per boss in the always-open boss panel. Only successful boss kills score; wipes retry the boss. Rare bosses remain optional. After the endboss and every subsequent boss kill, the host is prompted to finish or continue, with a summary of unscored mandatory/rare bosses. Even all-boss completion requires confirmation. Finishing scores only evaluated bosses; skipped bosses give neither points nor penalties. The host reads the identified boss combat session after combat, never overall/trash damage. Unidentifiable sessions, meter resets or reloads during measurement refund the series. No bank commission is deducted from Top-3 pots.

Both clients must install version 0.18.0, including the new file and updated TOC, then reload. Previous single-pick Damage Races should be cancelled/refunded before creating a new Top-3 bet. Verify live with a timed race, two-player and raid rosters, a boss wipe/retry, optional rares, tied scores, no correct tips and a meter reset.
