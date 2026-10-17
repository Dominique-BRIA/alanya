#!/usr/bin/env python3
"""Detecte les cles repetees dans les tables de traduction.

🔴 POURQUOI CE SCRIPT EXISTE : une cle repetee dans une `const Map` a fait
echouer la construction de l'APK, et RIEN ne l'avait vue avant.

⚠️ `flutter analyze` NE PEUT PAS LA VOIR. Une constante n'est evaluee qu'a la
compilation ; l'analyseur, lui, ne fait que lire le code. Le defaut ne se
manifeste donc qu'apres plusieurs minutes de Gradle, en CI — c'est-a-dire au
moment le plus cher et le plus tard possible.

⚠️ CE DEFAUT NAIT D'UNE FUSION, PAS D'UNE FAUTE DE FRAPPE. Deux branches
ajoutent le meme bloc de traductions a des endroits differents du fichier :
Git ne voit aucun conflit, et les deux blocs se retrouvent cote a cote. C'est
pour cela que la verification doit etre automatique — personne ne relit dix
mille lignes apres chaque fusion.

Rend 1 si un doublon existe, 0 sinon.
"""
import io
import re
import sys

FICHIER = "lib/l10n/app_localizations.dart"


def main() -> int:
    lignes = io.open(FICHIER, encoding="utf-8").read().split("\n")

    # Chaque table de langue s'ouvre par une ligne du genre `'fr': {`.
    debuts = [
        (i, re.match(r"'([a-z]{2})'\s*:\s*\{\s*$", l).group(1))
        for i, l in enumerate(lignes, 1)
        if re.match(r"'[a-z]{2}'\s*:\s*\{\s*$", l)
    ]

    # ⚠️ UN BANC QUI PASSE SUR UN FICHIER VIDE NE PROUVE RIEN. Si le format du
    # fichier change et que plus aucune table n'est reconnue, il faut echouer,
    # pas annoncer « aucun doublon ».
    if not debuts:
        print("ECHEC : aucune table de langue reconnue dans " + FICHIER)
        return 1

    faux = 0
    for n, (depart, langue) in enumerate(debuts):
        fin = debuts[n + 1][0] - 1 if n + 1 < len(debuts) else len(lignes)
        vus = {}
        for i in range(depart + 1, fin + 1):
            cle = re.match(r"\s*'([^']+)'\s*:", lignes[i - 1])
            if not cle:
                continue
            nom = cle.group(1)
            if nom in vus:
                print("DOUBLON [%s] %-32s lignes %d et %d"
                      % (langue, nom, vus[nom], i))
                faux += 1
            else:
                vus[nom] = i

    print("langues inspectees : %d - doublons : %d" % (len(debuts), faux))
    return 1 if faux else 0


if __name__ == "__main__":
    sys.exit(main())
