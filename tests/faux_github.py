#!/usr/bin/python3
"""Faux GitHub des tests de l'amorce : écoute sur 127.0.0.1 seulement, ne joint jamais le vrai service.

- GET /repos/tarnaub/le-lutin-bleu/releases/latest : 404 sans authentification ou avec un jeton sans accès (comme
  GitHub pour un dépôt privé), 401 avec un jeton inconnu, la release en JSON avec un jeton valide ; scénario « limite » :
  403 et x-ratelimit-remaining: 0, comme GitHub quand le quota est épuisé.
- GET /repos/tarnaub/le-lutin-bleu/releases/assets/<n> : redirection 302 vers http://localhost:<port>/telechargement/<n>,
  un autre nom d'hôte, comme le stockage de GitHub ; le journal note si l'en-tête Authorization y a été transmis.
- GET /tarnaub/le-lutin-bleu-installer/releases/latest/download/<fichier> : l'amorce publique, par une redirection vers
  le stockage (/stockage-public/<fichier>), comme un fichier de release ; scénario « amorce-coupee » : la moitié du
  fichier, puis la connexion coupée.

Le scénario courant est lu à chaque requête dans <racine>/scenario ; les fichiers d'une release sont dans
<racine>/releases/<scenario>/ (avec « tag » pour son étiquette, et « digest-faux » pour publier une empreinte fausse).
Le journal des requêtes ne contient jamais la valeur d'un jeton.
"""
import argparse
import hashlib
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

DEPOT = "tarnaub/le-lutin-bleu"
DEPOT_PUBLIC = "tarnaub/le-lutin-bleu-installer"
JETONS_VALIDES = {"jeton_essai_amorce_valide_0001", "jeton_essai_faux_gh_0002"}  # faux jetons des tests
JETONS_SANS_ACCES = {"jeton_essai_sans_acces_0003"}
FICHIERS = ["Le-Lutin-Bleu.zip", "installer-le-lutin-bleu.sh", "release-manifest.txt", "release-manifest.txt.sig"]


class Faux(BaseHTTPRequestHandler):
    racine = Path(".")
    port = 0
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        return

    def noter(self, statut, extra=""):
        auth = "présent" if self.headers.get("Authorization") else "absent"
        ligne = (f"{time.strftime('%H:%M:%S')} {self.command} {self.path} hôte={self.headers.get('Host')} "
                 f"Authorization={auth} scénario={self.scenario()} -> {statut} {extra}".rstrip())
        with open(self.racine / "journal-requetes.log", "a", encoding="utf-8") as f:
            f.write(ligne + "\n")

    def scenario(self):
        try:
            return (self.racine / "scenario").read_text(encoding="utf-8").strip() or "nominal"
        except OSError:
            return "nominal"

    def dossier(self):
        nom = self.scenario()
        d = self.racine / "releases" / nom
        return d if d.is_dir() else self.racine / "releases" / "nominal"

    def repondre(self, statut, corps=b"", type_="application/json", entetes=None):
        self.send_response(statut)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(corps)))
        for k, v in (entetes or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if corps:
            self.wfile.write(corps)

    def couper(self, corps, nom):
        """Annonce toute la taille, envoie la moitié et coupe : une coupure réseau en plein téléchargement."""
        self.noter(200, f"({nom}, coupé après {len(corps) // 2} octets sur {len(corps)})")
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps[: len(corps) // 2])
        self.wfile.flush()
        self.close_connection = True

    def jeton(self):
        valeur = self.headers.get("Authorization") or ""
        for prefixe in ("Bearer ", "token "):
            if valeur.startswith(prefixe):
                return valeur[len(prefixe):]
        return None if not valeur else ""

    def do_GET(self):
        chemin = urlsplit(self.path).path
        if chemin.startswith("/telechargement/"):
            return self.telechargement(chemin[len("/telechargement/"):])
        if chemin.startswith("/stockage-public/"):
            return self.stockage_public(chemin[len("/stockage-public/"):])
        prefixe_public = f"/{DEPOT_PUBLIC}/releases/latest/download/"
        if chemin.startswith(prefixe_public):
            nom = chemin[len(prefixe_public):]
            cible = f"http://localhost:{self.port}/stockage-public/{nom}"
            self.noter(302, f"-> {cible}")
            return self.repondre(302, b"", entetes={"Location": cible})
        if self.scenario() == "limite":
            self.noter(403, "(quota épuisé)")
            return self.repondre(403, b'{"message": "API rate limit exceeded"}',
                                 entetes={"x-ratelimit-remaining": "0", "x-ratelimit-limit": "5000"})
        jeton = self.jeton()
        if jeton is None or jeton in JETONS_SANS_ACCES:
            self.noter(404, "(dépôt privé : visiteur anonyme ou compte sans accès)")
            return self.repondre(404, b'{"message": "Not Found"}')
        if jeton not in JETONS_VALIDES:
            self.noter(401, "(jeton refusé)")
            return self.repondre(401, b'{"message": "Bad credentials"}')
        if chemin == f"/repos/{DEPOT}/releases/latest":
            self.noter(200, "(release)")
            return self.repondre(200, json.dumps(self.release()).encode("utf-8"))
        prefixe = f"/repos/{DEPOT}/releases/assets/"
        if chemin.startswith(prefixe) and chemin[len(prefixe):].isdigit():
            n = int(chemin[len(prefixe):])
            if 1 <= n <= len(FICHIERS):
                cible = f"http://localhost:{self.port}/telechargement/{n}?signature=essai"
                self.noter(302, f"-> {cible}")
                return self.repondre(302, b"", entetes={"Location": cible})
        self.noter(404)
        return self.repondre(404, b'{"message": "Not Found"}')

    def release(self):
        d = self.dossier()
        tag = (d / "tag").read_text(encoding="utf-8").strip()
        assets = []
        for n, nom in enumerate(FICHIERS, start=1):
            f = d / nom
            if not f.exists():
                continue
            digest = hashlib.sha256(f.read_bytes()).hexdigest()
            if nom == "installer-le-lutin-bleu.sh" and (d / "digest-faux").exists():
                digest = "0" * 64
            assets.append({
                "id": n, "name": f"Le-Lutin-Bleu-{tag}.zip" if nom == "Le-Lutin-Bleu.zip" else nom,
                "size": f.stat().st_size, "digest": "sha256:" + digest,
                "url": f"http://127.0.0.1:{self.port}/repos/{DEPOT}/releases/assets/{n}",
            })
        return {"tag_name": tag, "name": f"Le Lutin Bleu {tag}", "draft": False, "prerelease": False,
                "published_at": "2026-11-05T17:00:00Z", "assets": assets}

    def telechargement(self, reste):
        n = reste.split("?", 1)[0]
        if not n.isdigit() or not 1 <= int(n) <= len(FICHIERS):
            self.noter(404)
            return self.repondre(404, b"")
        nom = FICHIERS[int(n) - 1]
        corps = (self.dossier() / nom).read_bytes()
        if self.scenario() == "tronque-coupure" and nom == "installer-le-lutin-bleu.sh":
            return self.couper(corps, nom)
        self.noter(200, f"({nom}, {len(corps)} octets)")
        return self.repondre(200, corps, "application/octet-stream")

    def stockage_public(self, nom):
        f = self.racine / "public" / nom
        if "/" in nom or not f.is_file():
            self.noter(404)
            return self.repondre(404, b"Not Found", "text/plain")
        corps = f.read_bytes()
        if self.scenario() == "amorce-coupee":
            return self.couper(corps, nom)
        self.noter(200, f"(amorce publique {nom})")
        return self.repondre(200, corps, "application/octet-stream")


def main():
    p = argparse.ArgumentParser(description="Faux GitHub local des tests de l'amorce (127.0.0.1 seulement).")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--racine", required=True)
    a = p.parse_args()
    Faux.racine = Path(a.racine).resolve()
    Faux.port = a.port
    serveur = ThreadingHTTPServer(("127.0.0.1", a.port), Faux)
    print(f"Faux GitHub sur http://127.0.0.1:{a.port}", flush=True)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
