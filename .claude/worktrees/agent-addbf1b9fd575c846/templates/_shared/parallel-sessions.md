## Parallelbetrieb: mehrere Cloud-Sessions

Der Owner arbeitet an diesem Repo häufig mit mehreren Cloud-Sessions gleichzeitig (z. B. um mehrere Anforderungen parallel einzubringen). Fremde, session-fremde Änderungen im Working Tree/Board sind normal — kein Hinweis an den Owner nötig, solange keine eigene Arbeit dadurch verloren geht.

**Pflicht: eigener Branch UND eigener Worktree.** Ein reiner Branch-Wechsel reicht NICHT — er tauscht die Dateien im geteilten Hauptordner auch für jede andere dort aktive Session aus. Bevor eine Session in diesem Repo schreibend tätig wird (Board-Dateien, Specs, Code) und nicht sicher ausschließen kann, dass sie die einzige aktive Session ist, MUSS sie zuerst `EnterWorktree` aufrufen (eigener Ordner unter `.claude/worktrees/`, eigener Branch, gleiche Git-Historie wie der Hauptordner). Am Ende der Session: Änderungen committen + pushen, danach `ExitWorktree` (`action: "remove"`, sobald nichts mehr daraus gebraucht wird).

**Warum:** `git checkout`/`reset`/`clean` im Hauptordner wirkt sich auf ALLE dort aktiven Prozesse aus — auch auf noch nicht committete Änderungen einer anderen Session. Das führt zu stillem Datenverlust statt zu einem sichtbaren Konflikt. *(Vorfall 2026-07-02, dev-gui: ein `/requirement`-Lauf verlor zweimal frisch angelegte Board-Items, weil eine parallele Headless-Flow-Session im selben Hauptordner reset/clean ausführte.)*

Ausnahme: rein lesende Sessions (nur ansehen, keine Schreiboperation geplant) können im Hauptordner bleiben.
