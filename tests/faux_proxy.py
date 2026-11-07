#!/usr/bin/python3
"""Faux proxy HTTP des tests de l'amorce : relaie les requêtes « GET http://127.0.0.1:… » ou « GET http://localhost:… »
vers le faux GitHub et refuse toute autre destination. Écoute sur 127.0.0.1 seulement. Son journal note chaque requête
relayée et la présence de l'en-tête Authorization, jamais sa valeur.
"""
import argparse
import http.client
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

HOTES = {"127.0.0.1", "localhost"}


class Proxy(BaseHTTPRequestHandler):
    journal = Path("proxy.log")
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        return

    def noter(self, texte):
        auth = "présent" if self.headers.get("Authorization") else "absent"
        with open(self.journal, "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {self.command} {self.path} Authorization={auth} {texte}\n")

    def refuser(self, statut):
        self.noter(f"-> refusé {statut}")
        self.send_response(statut)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        cible = urlsplit(self.path)
        if cible.scheme != "http" or cible.hostname not in HOTES or not cible.port:
            return self.refuser(403)
        entetes = {k: v for k, v in self.headers.items() if k.lower() not in ("proxy-connection", "connection")}
        chemin = cible.path + (f"?{cible.query}" if cible.query else "")
        try:
            amont = http.client.HTTPConnection("127.0.0.1", cible.port, timeout=30)
            amont.request("GET", chemin, headers=entetes)
            reponse = amont.getresponse()
            corps = reponse.read()
        except (OSError, http.client.HTTPException):
            return self.refuser(502)
        self.noter(f"-> {reponse.status}")
        self.send_response(reponse.status)
        for k, v in reponse.getheaders():
            if k.lower() not in ("connection", "transfer-encoding", "content-length"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def do_CONNECT(self):
        return self.refuser(403)


def main():
    p = argparse.ArgumentParser(description="Faux proxy local des tests de l'amorce (127.0.0.1 seulement).")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--journal", required=True)
    a = p.parse_args()
    Proxy.journal = Path(a.journal)
    serveur = ThreadingHTTPServer(("127.0.0.1", a.port), Proxy)
    print(f"Faux proxy sur http://127.0.0.1:{a.port}", flush=True)
    try:
        serveur.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
