#!/usr/bin/env python3
"""Les routes que le mobile appelle existent-elles, avec CE verbe ?

🔴 POURQUOI CE SCRIPT EXISTE. Le mobile publiait ses clés par
`POST /api/e2ee/cles`. Cette route n'exporte que `GET`, `PUT` et `DELETE` : le
serveur répondait 405, et le mobile n'a JAMAIS publié la moindre clé. Personne
ne pouvait lui écrire — en ligne ou non.

⚠️ RIEN NE POUVAIT LE VOIR, ET C'EST LE POINT.

  - `dart analyze` ne connaît pas les routes : un chemin est une chaîne.
  - le banc d'interopérabilité branche une FAUSSE fonction réseau — il éprouve
    le PROTOCOLE Signal, jamais le CONTRAT HTTP.
  - `demarrer()` rattrape toute exception, donc l'échec était silencieux.

Trois filets, et le défaut passait entre les trois. C'est exactement le genre
de trou qu'un contrôle statique ferme pour presque rien.

⚠️ CE SCRIPT NE VÉRIFIE QUE LE VERBE ET LE CHEMIN. Les noms de champs du corps
lui échappent — c'était la deuxième erreur du même appel. Un contrôle plus fin
demanderait de lire le corps des deux côtés ; celui-ci attrape déjà la classe
de défaut la plus coûteuse.

Usage :
    python outils/contrat_routes.py [chemin/vers/backend-alanya]

Sans argument, cherche le backend à côté de ce dépôt.
"""
import io
import os
import re
import sys

MOBILE = "lib/services/e2ee"


def routes_du_backend(racine):
    """{'/api/e2ee/cles': {'GET', 'PUT', 'DELETE'}, …}"""
    base = os.path.join(racine, "src", "app", "api")
    trouve = {}
    for dossier, _, fichiers in os.walk(base):
        if "route.ts" not in fichiers:
            continue
        chemin = "/api/" + os.path.relpath(dossier, base).replace(os.sep, "/")
        src = io.open(os.path.join(dossier, "route.ts"), encoding="utf-8").read()
        verbes = set(
            re.findall(
                r"^export\s+(?:const|async\s+function)\s+(GET|POST|PUT|PATCH|DELETE)",
                src,
                re.M,
            )
        )
        trouve[chemin] = verbes
    return trouve


def appels_du_mobile():
    """[(fichier, ligne, verbe, chemin)]"""
    appels = []
    for dossier, _, fichiers in os.walk(MOBILE):
        for f in fichiers:
            if not f.endswith(".dart"):
                continue
            p = os.path.join(dossier, f)
            for n, l in enumerate(io.open(p, encoding="utf-8").read().split("\n"), 1):
                for verbe, chemin in re.findall(
                    r"api\(\s*'(GET|POST|PUT|PATCH|DELETE)'\s*,\s*'([^']+)'", l
                ):
                    appels.append((p, n, verbe, chemin))
    return appels


def gabarit(chemin):
    """`/api/conversations/abc/messages` → `/api/conversations/[id]/messages`.

    ⚠️ LES SEGMENTS INTERPOLÉS SONT DES PARAMÈTRES. `$convId` en Dart devient
    `[id]` côté Next : on ne peut pas les comparer littéralement.
    """
    chemin = chemin.split("?")[0].rstrip("/")
    return [s for s in chemin.split("/") if s]


def correspond(appele, declare):
    a, d = gabarit(appele), gabarit(declare)
    if len(a) != len(d):
        return False
    for sa, sd in zip(a, d):
        if sd.startswith("[") and sd.endswith("]"):
            continue
        if "$" in sa:  # segment interpolé côté Dart
            continue
        if sa != sd:
            return False
    return True


def main():
    racine = sys.argv[1] if len(sys.argv) > 1 else os.path.join("..", "backend-alanya")
    if not os.path.isdir(os.path.join(racine, "src", "app", "api")):
        # ⚠️ UN BANC QUI PASSE SANS RIEN LIRE NE PROUVE RIEN. On échoue, et on
        # dit pourquoi, plutôt qu'annoncer « aucun problème ».
        print("ECHEC : backend introuvable en '%s'." % racine)
        print("        Donnez son chemin en argument.")
        return 1

    routes = routes_du_backend(racine)
    appels = appels_du_mobile()
    if not appels:
        print("ECHEC : aucun appel `api('VERBE', '/chemin')` trouvé dans " + MOBILE)
        return 1

    faux = 0
    for fichier, ligne, verbe, chemin in appels:
        candidats = [d for d in routes if correspond(chemin, d)]
        if not candidats:
            print("ROUTE INCONNUE  %s %s" % (verbe, chemin))
            print("                %s:%d" % (fichier, ligne))
            faux += 1
            continue
        verbes = set()
        for c in candidats:
            verbes |= routes[c]
        if verbe not in verbes:
            print("VERBE REFUSE    %s %s" % (verbe, chemin))
            print("                la route accepte : %s" % ", ".join(sorted(verbes)))
            print("                %s:%d" % (fichier, ligne))
            faux += 1

    print("appels inspectes : %d - incoherences : %d" % (len(appels), faux))
    return 1 if faux else 0


if __name__ == "__main__":
    sys.exit(main())
