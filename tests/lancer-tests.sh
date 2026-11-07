#!/bin/bash
# lancer-tests.sh — tests de l'amorce contre un faux GitHub local (127.0.0.1), sans jamais joindre le vrai GitHub.
#
# Prépare dans tests/.essais/ (ignoré par git) deux paires de clés d'essai, une release factice par scénario, signée
# comme le fait scripts/signer_release.sh du dépôt privé, et une copie de l'amorce dont seule la clé publique est
# remplacée par la clé d'essai ; démarre le faux GitHub et le faux proxy, puis joue chaque cas et vérifie le code de
# sortie, le témoin de l'installateur factice, le message attendu et le nettoyage. gh n'est jamais le vrai :
# LUTIN_AMORCE_GH est toujours nommé (vide, chemin absent ou tests/faux-gh/gh). Par précaution, toute requête https part
# vers un proxy fermé et échoue.
#   bash tests/lancer-tests.sh
# Variables facultatives : LUTIN_CLE_REFERENCE (la clé publique du dépôt privé, seed/release-signing-key.pub) et
# LUTIN_INSTALLATEUR_REFERENCE (son installer-le-lutin-bleu.sh), par défaut cherchés dans ../le-lutin-bleu.
set -u
set -o pipefail

RACINE="$(cd "$(dirname "$0")/.." && pwd -P)"
TESTS="$RACINE/tests"
ESSAIS="$TESTS/.essais"
FAUX="$ESSAIS/faux-github"
CLES="$ESSAIS/cles"
SORTIES="$ESSAIS/sorties"
TEMOINS="$ESSAIS/temoins"
TRAVAIL_AMORCE="$ESSAIS/travail-amorce"
GH_ETAT="$ESSAIS/faux-gh-etat"
JOURNAL_REQ="$FAUX/journal-requetes.log"
JOURNAL_PROXY="$ESSAIS/journal-proxy.log"
JOURNAL_GH="$ESSAIS/journal-faux-gh.log"
AMORCE="$RACINE/amorce-le-lutin-bleu.sh"
AMORCE_ESSAI="$ESSAIS/amorce-essai.sh"
FAUX_GH="$TESTS/faux-gh/gh"
PORT=18765
PORT_PROXY=18766
PORT_FERME=18799
API="http://127.0.0.1:$PORT"
URL_PUBLIQUE="$API/tarnaub/le-lutin-bleu-installer/releases/latest/download/amorce-le-lutin-bleu.sh"
JETON_VALIDE="jeton_essai_amorce_valide_0001"  # faux jetons, les mêmes que faux_github.py
JETON_GH="jeton_essai_faux_gh_0002"
JETON_SANS_ACCES="jeton_essai_sans_acces_0003"
CLE_REF="${LUTIN_CLE_REFERENCE:-$RACINE/../le-lutin-bleu/app/lutin_bleu/seed/release-signing-key.pub}"
INSTALLATEUR_REF="${LUTIN_INSTALLATEUR_REFERENCE:-$RACINE/../le-lutin-bleu/installer-le-lutin-bleu.sh}"
TAG="V09.999"
FICHIERS_SHELL=("$AMORCE" "$RACINE/scripts/publier.sh" "$TESTS/lancer-tests.sh" "$FAUX_GH" "$TESTS/installateur-factice.sh")

# les descripteurs 3 à 9 hérités de qui lance les tests faussent le contrôle des descripteurs transmis à l'installateur
exec 3<&- 4<&- 5<&- 6<&- 7<&- 8<&- 9<&-
export https_proxy="http://127.0.0.1:$PORT_FERME" HTTPS_PROXY="http://127.0.0.1:$PORT_FERME"
unset http_proxy HTTP_PROXY ALL_PROXY all_proxy NO_PROXY no_proxy GH_TOKEN GITHUB_TOKEN GH_HOST

for p in "$PORT" "$PORT_PROXY" "$PORT_FERME"; do
  if /usr/sbin/lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "le port $p est déjà occupé : tests annulés" >&2
    exit 1
  fi
done

# --- préparation ------------------------------------------------------------------------------------------------------

sha() { /usr/bin/shasum -a 256 "$1" | cut -d' ' -f1; }

manifeste() {  # manifeste DOSSIER INSTALLATEUR TAG [DEPOT] [FORMAT]
  {
    printf 'format=%s\n' "${5:-lutin-bleu-release-v1}"
    printf 'tag=%s\n' "$3"
    printf 'repository=%s\n' "${4:-tarnaub/le-lutin-bleu}"
    printf 'sha256_zip=%s\n' "$(sha "$ESSAIS/sources/zip")"
    printf 'sha256_installer=%s\n' "$(sha "$2")"
  } > "$1/release-manifest.txt"
}

signer() {  # signer DOSSIER CLE
  rm -f "$1/release-manifest.txt.sig"
  /usr/bin/ssh-keygen -Y sign -q -n le-lutin-bleu-release@lelutinbleu.com -f "$2" "$1/release-manifest.txt"
}

release() {  # release SCENARIO TAG INSTALLATEUR_SERVI : le dossier de la release, sans manifeste
  local d="$FAUX/releases/$1"
  mkdir -p "$d"
  printf '%s\n' "$2" > "$d/tag"
  cp "$ESSAIS/sources/zip" "$d/Le-Lutin-Bleu.zip"
  cp "$3" "$d/installer-le-lutin-bleu.sh"
}

preparer() {
  local inst alt d cle taille
  rm -rf "$ESSAIS"
  mkdir -p "$CLES" "$FAUX/releases" "$FAUX/public" "$SORTIES" "$TEMOINS" "$TRAVAIL_AMORCE" "$GH_ETAT" \
    "$ESSAIS/tronquees" "$ESSAIS/telecharge" "$ESSAIS/sources" "$ESSAIS/naif"
  chmod 700 "$CLES"
  /usr/bin/ssh-keygen -q -t ed25519 -N "" -C essai@tests -f "$CLES/cle-essai"
  /usr/bin/ssh-keygen -q -t ed25519 -N "" -C pirate@tests -f "$CLES/cle-pirate"
  inst="$ESSAIS/sources/installateur.sh"
  alt="$ESSAIS/sources/installateur-altere.sh"
  cp "$TESTS/installateur-factice.sh" "$inst"
  cp "$inst" "$alt"
  # shellcheck disable=SC2016  # la variable reste littérale : c'est l'installateur altéré qui la lira
  printf 'touch "${LUTIN_TEST_TEMOIN}.pirate"\n' >> "$alt"
  printf 'zip factice des tests\n' > "$ESSAIS/sources/zip"
  VMIN="$(sed -n 's/^  VERSION_MINIMALE="\(V[0-9][0-9]\.[0-9][0-9][0-9]\)"$/\1/p' "$AMORCE")"
  [ -n "$VMIN" ] || { echo "VERSION_MINIMALE introuvable dans l'amorce" >&2; exit 1; }

  release nominal "$TAG" "$inst"
  manifeste "$FAUX/releases/nominal" "$inst" "$TAG"
  signer "$FAUX/releases/nominal" "$CLES/cle-essai"
  # l'installateur remplacé sur GitHub, manifeste et signature d'origine
  release installateur-altere "$TAG" "$alt"
  cp "$FAUX/releases/nominal/release-manifest.txt" "$FAUX/releases/nominal/release-manifest.txt.sig" "$FAUX/releases/installateur-altere/"
  # l'empreinte du manifeste réécrite, sans pouvoir le signer de nouveau
  release manifeste-altere "$TAG" "$alt"
  manifeste "$FAUX/releases/manifeste-altere" "$alt" "$TAG"
  cp "$FAUX/releases/nominal/release-manifest.txt.sig" "$FAUX/releases/manifeste-altere/"
  # tout cohérent, mais signé par une autre clé
  release autre-cle "$TAG" "$alt"
  manifeste "$FAUX/releases/autre-cle" "$alt" "$TAG"
  signer "$FAUX/releases/autre-cle" "$CLES/cle-pirate"
  # un manifeste valide d'un autre dépôt, d'une autre version, d'un format inconnu
  release rejeu-autre-depot "$TAG" "$inst"
  manifeste "$FAUX/releases/rejeu-autre-depot" "$inst" "$TAG" autre/depot
  signer "$FAUX/releases/rejeu-autre-depot" "$CLES/cle-essai"
  release rejeu-autre-version "$TAG" "$inst"
  manifeste "$FAUX/releases/rejeu-autre-version" "$inst" V09.998
  signer "$FAUX/releases/rejeu-autre-version" "$CLES/cle-essai"
  release format-inconnu "$TAG" "$inst"
  manifeste "$FAUX/releases/format-inconnu" "$inst" "$TAG" tarnaub/le-lutin-bleu lutin-bleu-release-v2
  signer "$FAUX/releases/format-inconnu" "$CLES/cle-essai"
  # un manifeste signé qui répète un champ (le premier conforme, le second non) : lu « premier » ici, « dernier » par l'app
  release champ-repete "$TAG" "$inst"
  manifeste "$FAUX/releases/champ-repete" "$inst" "$TAG"
  printf 'sha256_installer=%s\n' "$(printf '0%.0s' {1..64})" >> "$FAUX/releases/champ-repete/release-manifest.txt"
  signer "$FAUX/releases/champ-repete" "$CLES/cle-essai"
  # une ancienne release authentique republiée comme dernière ; et la version minimale elle-même
  release ancienne-version V01.001 "$inst"
  manifeste "$FAUX/releases/ancienne-version" "$inst" V01.001
  signer "$FAUX/releases/ancienne-version" "$CLES/cle-essai"
  release version-minimale "$VMIN" "$inst"
  manifeste "$FAUX/releases/version-minimale" "$inst" "$VMIN"
  signer "$FAUX/releases/version-minimale" "$CLES/cle-essai"
  # empreinte publiée par GitHub différente, manifeste juste
  release digest-faux "$TAG" "$inst"
  cp "$FAUX/releases/nominal/release-manifest.txt" "$FAUX/releases/nominal/release-manifest.txt.sig" "$FAUX/releases/digest-faux/"
  touch "$FAUX/releases/digest-faux/digest-faux"
  # un installateur coupé de moitié servi comme complet
  release tronque-contenu "$TAG" "$inst"
  taille="$(wc -c < "$inst" | tr -d ' ')"
  head -c $((taille / 2)) "$inst" > "$FAUX/releases/tronque-contenu/installer-le-lutin-bleu.sh"
  cp "$FAUX/releases/nominal/release-manifest.txt" "$FAUX/releases/nominal/release-manifest.txt.sig" "$FAUX/releases/tronque-contenu/"
  # publiée, pas encore signée
  release non-signee "$TAG" "$inst"
  # tronque-coupure, limite, amorce-coupee : les fichiers du nominal ; c'est le serveur qui coupe ou refuse
  for d in tronque-coupure limite amorce-coupee; do cp -R "$FAUX/releases/nominal" "$FAUX/releases/$d"; done

  cle="$(awk '{print $1" "$2}' "$CLES/cle-essai.pub")"
  sed "s|^  CLE_PUBLIQUE=\".*\"\$|  CLE_PUBLIQUE=\"$cle\"|" "$AMORCE" > "$AMORCE_ESSAI"
  if [ "$(diff "$AMORCE" "$AMORCE_ESSAI" | grep -c '^[<>]')" != 2 ] || ! grep -q "CLE_PUBLIQUE=\"$cle\"" "$AMORCE_ESSAI"; then
    echo "l'amorce d'essai devrait ne différer que par la clé publique" >&2
    exit 1
  fi
  cp "$AMORCE_ESSAI" "$FAUX/public/amorce-le-lutin-bleu.sh"
  echo nominal > "$FAUX/scenario"
  : > "$JOURNAL_REQ"
  : > "$JOURNAL_PROXY"
  : > "$JOURNAL_GH"
}

preparer

/usr/bin/python3 "$TESTS/faux_github.py" --port "$PORT" --racine "$FAUX" > "$ESSAIS/faux-github.out" 2>&1 &
SERVEUR=$!
/usr/bin/python3 "$TESTS/faux_proxy.py" --port "$PORT_PROXY" --journal "$JOURNAL_PROXY" > "$ESSAIS/faux-proxy.out" 2>&1 &
PROXY=$!
trap 'kill "$SERVEUR" "$PROXY" 2>/dev/null; wait "$SERVEUR" "$PROXY" 2>/dev/null' EXIT
for _ in $(seq 1 50); do
  [ "$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' "$API/pret" 2>/dev/null)" != 000 ] \
    && [ "$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT_PROXY/" 2>/dev/null)" != 000 ] && break
  sleep 0.1
done
: > "$JOURNAL_REQ"
: > "$JOURNAL_PROXY"

# --- outils des tests -------------------------------------------------------------------------------------------------

REUSSIS=0 ECHOUES=0 IGNORES=0
RESULTATS="$ESSAIS/resultats.md"
{
  echo "# Résultats des tests de l'amorce ($(date '+%d/%m/%Y à %H:%M:%S'), bash $(/bin/bash -c 'echo $BASH_VERSION'))"
  echo ""
  echo "| N° | Test | Attendu | Résultat |"
  echo "|---|---|---|---|"
} > "$RESULTATS"

consigner() {  # consigner NUM NOM ATTENDU OK|ECHEC|IGNORE [DETAIL]
  local etat="réussi"
  case "$4" in
    OK) REUSSIS=$((REUSSIS + 1)) ;;
    IGNORE) IGNORES=$((IGNORES + 1)); etat="ignoré ${5:-}" ;;
    *) ECHOUES=$((ECHOUES + 1)); etat="**ÉCHEC** ${5:-}" ;;
  esac
  printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$etat" >> "$RESULTATS"
  printf '%-4s %-44s %s\n' "$1" "$2" "$etat"
}

bilan() {  # bilan NUM NOM ATTENDU DETAIL : réussi si DETAIL est vide
  if [ -z "$4" ]; then consigner "$1" "$2" "$3" OK; else consigner "$1" "$2" "$3" ECHEC "($4)"; fi
}

ENV_ESSAI=()
lancer_amorce() {  # lancer_amorce NOM SCENARIO ENTREE [ARGS...] : sortie dans $SORTIES/NOM.txt, code dans STATUT
  local nom="$1" scenario="$2" entree="$3"
  shift 3
  echo "$scenario" > "$FAUX/scenario"
  rm -f "$TEMOINS/$nom.txt" "$TEMOINS/$nom.txt.pirate"
  if [ "${GH_CONNECTE:-0}" = 1 ]; then touch "$GH_ETAT/connecte"; else rm -f "$GH_ETAT/connecte"; fi
  STATUT=0
  printf '%b' "$entree" | env ${ENV_ESSAI[@]+"${ENV_ESSAI[@]}"} \
      LUTIN_AMORCE_API="${API_ESSAI:-$API}" LUTIN_AMORCE_GH="${GH_ESSAI:-}" LUTIN_AMORCE_TRAVAIL="$TRAVAIL_AMORCE" \
      LUTIN_TEST_TEMOIN="$TEMOINS/$nom.txt" FAUX_GH_ETAT="$GH_ETAT" FAUX_GH_API="${GH_API:-$API}" \
      FAUX_GH_JOURNAL="$JOURNAL_GH" FAUX_GH_JETON="${GH_JETON:-$JETON_GH}" FAUX_GH_CONNEXION="${GH_CONNEXION:-echec}" \
      /bin/bash "${AMORCE_LANCEE:-$AMORCE_ESSAI}" "$@" > "$SORTIES/$nom.txt" 2>&1 || STATUT=$?
}

travail_vide() { [ -z "$(find "$TRAVAIL_AMORCE" -mindepth 1 -print -quit)" ]; }
requetes_api() { grep -c '/repos/' "$JOURNAL_REQ" || true; }

verifier_refus() {  # verifier_refus NUM NOM SCENARIO ENTREE MOTIF ATTENDU [ARGS...]
  local num="$1" nom="$2" scenario="$3" entree="$4" motif="$5" attendu="$6" detail=""
  shift 6
  lancer_amorce "$nom" "$scenario" "$entree" "$@"
  [ "$STATUT" -ne 0 ] || detail="code 0"
  [ ! -e "$TEMOINS/$nom.txt" ] || detail="$detail installateur lancé"
  [ ! -e "$TEMOINS/$nom.txt.pirate" ] || detail="$detail ligne pirate exécutée"
  grep -q -- "$motif" "$SORTIES/$nom.txt" || detail="$detail message attendu absent"
  travail_vide || detail="$detail dossier de travail non nettoyé"
  bilan "$num" "$nom" "$attendu" "$detail"
}

controler_succes() {  # controler_succes NOM MODE : détail des écarts dans DETAIL (MODE jeton ou gh)
  local nom="$1" mode="$2" t="$TEMOINS/$1.txt"
  DETAIL=""
  [ "$STATUT" -eq 0 ] || DETAIL="code $STATUT"
  [ -f "$t" ] || DETAIL="$DETAIL témoin absent"
  [ ! -e "$t.pirate" ] || DETAIL="$DETAIL ligne pirate exécutée"
  grep -q "Signature vérifiée" "$SORTIES/$nom.txt" || DETAIL="$DETAIL signature non annoncée"
  grep -q -- "--source github --version ${TAG_ATTENDU:-$TAG} --depot tarnaub/le-lutin-bleu --cle-publique ssh-ed25519 " "$t" 2>/dev/null \
    || DETAIL="$DETAIL arguments inattendus"
  if [ "$mode" = jeton ]; then
    grep -q "jeton reçu par le descripteur 3 : oui (${#JETON_VALIDE} caractères)" "$t" 2>/dev/null || DETAIL="$DETAIL jeton non transmis"
  else
    grep -q "jeton reçu par le descripteur 3 : non" "$t" 2>/dev/null || DETAIL="$DETAIL descripteur 3 inattendu"
  fi
  grep -q "descripteur 4 ouvert : non" "$t" 2>/dev/null || DETAIL="$DETAIL descripteur 4 transmis"
  travail_vide || DETAIL="$DETAIL dossier de travail non nettoyé"
}

verifier_succes() {  # verifier_succes NUM NOM SCENARIO ENTREE ATTENDU MODE [ARGS...]
  local num="$1" nom="$2" scenario="$3" entree="$4" attendu="$5" mode="$6"
  shift 6
  lancer_amorce "$nom" "$scenario" "$entree" "$@"
  controler_succes "$nom" "$mode"
  bilan "$num" "$nom" "$attendu" "$DETAIL"
}

avant() {  # avant FICHIER MOTIF1 MOTIF2 : MOTIF1 apparaît, et avant MOTIF2
  local a b
  a="$(grep -n -- "$2" "$1" | head -n 1 | cut -d: -f1)"
  b="$(grep -n -- "$3" "$1" | head -n 1 | cut -d: -f1)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}

echo "Tests de l'amorce (bash $(/bin/bash -c 'echo $BASH_VERSION')), faux GitHub $API, version minimale $VMIN"

# --- analyse statique et contenu -------------------------------------------------------------------------------------

detail=""
/opt/homebrew/bin/shellcheck -s bash -x "${FICHIERS_SHELL[@]}" > "$SORTIES/T01-shellcheck.txt" 2>&1 || detail="voir sorties/T01-shellcheck.txt"
bilan T01 "shellcheck (5 scripts)" "aucun avertissement" "$detail"

detail=""
for f in "${FICHIERS_SHELL[@]}"; do /bin/bash -n "$f" 2>>"$SORTIES/T02-bash-n.txt" || detail="$detail $(basename "$f")"; done
bilan T02 "bash 3.2 -n (5 scripts)" "syntaxe valide" "$detail"

# bash 3.2 lit une variable suivie d'un caractère non ASCII (TAG suivi de « … ») comme une variable « TAG\xe2 » : elle
# s'écrit entre accolades (shellcheck ne le voit pas)
if LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "${FICHIERS_SHELL[@]}" > "$SORTIES/T03-accents.txt"; then
  consigner T03 "variables collées à un accent" "aucune" ECHEC "(voir sorties/T03-accents.txt)"
else
  consigner T03 "variables collées à un accent" "aucune" OK
fi

detail=""
[ "$(tail -n 1 "$AMORCE")" = 'amorce_principale "$@"' ] || detail="dernière ligne inattendue"
sed '$d' "$AMORCE" > "$ESSAIS/amorce-sans-derniere-ligne.sh"
PATH=/nonexistent /bin/bash -x "$ESSAIS/amorce-sans-derniere-ligne.sh" > "$SORTIES/T04-trace.txt" 2>&1 || detail="$detail code non nul"
[ ! -s "$SORTIES/T04-trace.txt" ] || detail="$detail commande hors fonction (voir sorties/T04-trace.txt)"
bilan T04 "enveloppe en fonctions" "seule commande : la dernière ligne" "$detail"

# T05 : rien d'interne ni de personnel dans l'amorce et ses documents publics. Ce dépôt est destiné à être public :
# les noms à refuser n'y sont pas écrits. Ils sont dans un fichier local ignoré par git (LUTIN_TERMES_INTERNES, par
# défaut .termes-internes à la racine), un motif grep -E par ligne ; les lignes vides et les commentaires sont ignorés.
TERMES_LOCAUX="${LUTIN_TERMES_INTERNES:-$RACINE/.termes-internes}"
PUBLICS=("$AMORCE" "$RACINE/README.md" "$RACINE/SECURITY.md" "$RACINE/LICENSE" "$RACINE/scripts/publier.sh")
grep -inE '\.internal|intranet' "${PUBLICS[@]}" > "$SORTIES/T05-interne.txt"
if [ -s "$TERMES_LOCAUX" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$TERMES_LOCAUX" > "$ESSAIS/termes-internes.txt"
  grep -inE -f "$ESSAIS/termes-internes.txt" "${PUBLICS[@]}" >> "$SORTIES/T05-interne.txt"
fi
if [ -s "$SORTIES/T05-interne.txt" ]; then
  consigner T05 "rien d'interne ni de personnel" "aucun nom interne ou personnel" ECHEC "(voir sorties/T05-interne.txt)"
elif [ ! -s "$TERMES_LOCAUX" ]; then
  consigner T05 "rien d'interne ni de personnel" "aucun nom interne ou personnel" IGNORE "(liste locale absente : $TERMES_LOCAUX)"
else
  consigner T05 "rien d'interne ni de personnel" "aucun nom interne ou personnel" OK
fi

cle_amorce="$(sed -n 's/^  CLE_PUBLIQUE="\(.*\)"$/\1/p' "$AMORCE")"
if [ -f "$CLE_REF" ]; then
  cle_ref="$(grep -E '^(ssh-ed25519|sk-ssh-ed25519@openssh\.com) ' "$CLE_REF" | head -n 1 | awk '{print $1" "$2}')"
  if [ -n "$cle_ref" ] && [ "$cle_ref" = "$cle_amorce" ]; then
    consigner T06 "clé embarquée = clé du dépôt privé" "identiques" OK
  else
    consigner T06 "clé embarquée = clé du dépôt privé" "identiques" ECHEC "(amorce : $cle_amorce ; référence : $cle_ref)"
  fi
else
  consigner T06 "clé embarquée = clé du dépôt privé" "identiques" IGNORE "(référence absente : $CLE_REF)"
fi

detail=""
empreinte="$(sha "$AMORCE")"
version_amorce="$(sed -n 's/^  AMORCE_VERSION="\(.*\)"$/\1/p' "$AMORCE")"
grep -q "$empreinte" "$RACINE/README.md" || detail="empreinte $empreinte absente du README"
grep -q "v$version_amorce" "$RACINE/README.md" || detail="$detail version v$version_amorce absente du README"
bilan T07 "README à jour (empreinte, version)" "empreinte $empreinte" "$detail"

if [ -f "$INSTALLATEUR_REF" ]; then
  detail=""
  for opt in --source --version --depot --cle-publique --dossier --sans-lancement --sans-restauration --restaurer; do
    grep -qE -- "(^|[[:space:]|])${opt}[|)]" "$INSTALLATEUR_REF" || detail="$detail $opt"
  done
  bilan T08 "options transmises connues de l'installateur" "toutes acceptées" "${detail:+inconnues :$detail}"
  if grep -q LUTIN_BLEU_JETON_FD "$INSTALLATEUR_REF"; then
    echo "     info : l'installateur de référence lit LUTIN_BLEU_JETON_FD"
  else
    echo "     info : l'installateur de référence ne lit pas encore LUTIN_BLEU_JETON_FD (patch du dépôt principal)"
  fi
else
  consigner T08 "options transmises connues de l'installateur" "toutes acceptées" IGNORE "(référence absente)"
fi

# --- options ---------------------------------------------------------------------------------------------------------

n0="$(requetes_api)"
lancer_amorce aide nominal "" --aide
detail=""
[ "$STATUT" -eq 0 ] || detail="code $STATUT"
grep -q -- "--sans-lancement" "$SORTIES/aide.txt" || detail="$detail aide absente"
[ "$(requetes_api)" = "$n0" ] || detail="$detail requête envoyée"
bilan T09 "--aide" "aide, aucune requête" "$detail"

verifier_refus T10 option-inconnue nominal "" "option inconnue" "refus sans requête" --version V01.001
n0="$(requetes_api)"
verifier_refus T11 jeton-dans-la-commande nominal "" "ne s'écrit jamais dans la commande" \
  "refus avant tout appel réseau" github_pat_FAUX_POUR_ESSAI_0004
verifier_refus T11b jeton-dans-une-option nominal "" "ne s'écrit jamais dans la commande" \
  "refus avant tout appel réseau" --jeton=ghp_FAUXPOURESSAI0005
[ "$(requetes_api)" = "$n0" ] || consigner T11c "jeton dans la commande (réseau)" "aucune requête" ECHEC "(requêtes envoyées)"

# --- accès au dépôt privé -------------------------------------------------------------------------------------------

verifier_succes T12 nominal-jeton nominal "$JETON_VALIDE\n" "signature vérifiée, installateur lancé, jeton par le descripteur 3" jeton
detail=""
avant "$SORTIES/nominal-jeton.txt" "TOUS les dépôts" "Jeton GitHub (Entrée" || detail="portée non dite avant la saisie"
grep -q "y compris ceux de votre" "$SORTIES/nominal-jeton.txt" || detail="$detail employeur non cité"
avant "$SORTIES/nominal-jeton.txt" "gh n'est pas installé" "Jeton GitHub (Entrée" || detail="$detail gh absent non dit"
grep -q "durée la plus courte (7 jours)" "$SORTIES/nominal-jeton.txt" || detail="$detail durée courte non conseillée"
grep -q "settings/tokens/new?scopes=repo" "$SORTIES/nominal-jeton.txt" || detail="$detail lien du jeton classique absent"
grep -q "L'amorce ne garde rien" "$SORTIES/nominal-jeton.txt" || detail="$detail « ne garde rien » absent"
bilan T12b "portée dite avant le jeton" "avertissement complet avant la saisie" "$detail"

if grep -q "/telechargement/.*Authorization=présent" "$JOURNAL_REQ"; then
  consigner T13 "jeton non transmis au stockage" "Authorization absent après redirection" ECHEC "(jeton envoyé au stockage)"
elif grep -q "/telechargement/.*Authorization=absent" "$JOURNAL_REQ"; then
  consigner T13 "jeton non transmis au stockage" "Authorization absent après redirection" OK
else
  consigner T13 "jeton non transmis au stockage" "Authorization absent après redirection" ECHEC "(aucun téléchargement noté)"
fi

lancer_amorce nominal-options nominal "$JETON_VALIDE\n" --dossier "$ESSAIS/dossier essai" --sans-lancement --sans-restauration
controler_succes nominal-options jeton
grep -q -- "--dossier $ESSAIS/dossier essai --sans-lancement --sans-restauration" "$TEMOINS/nominal-options.txt" 2>/dev/null \
  || DETAIL="$DETAIL options non transmises"
bilan T14 nominal-options "options transmises à l'installateur" "$DETAIL"

verifier_succes T15 jeton-refuse-puis-bon nominal "faux_jeton_0006\n$JETON_VALIDE\n" "1er refusé (401), 2e accepté" jeton
grep -q "jeton refusé par GitHub" "$SORTIES/jeton-refuse-puis-bon.txt" \
  || consigner T15b "motif du refus 401" "« jeton refusé par GitHub »" ECHEC
verifier_succes T16 jeton-sans-acces-puis-bon nominal "$JETON_SANS_ACCES\n$JETON_VALIDE\n" "1er sans accès (404), 2e accepté" jeton
grep -q "ce compte ne voit pas tarnaub/le-lutin-bleu" "$SORTIES/jeton-sans-acces-puis-bon.txt" \
  || consigner T16b "motif du refus 404" "« ce compte ne voit pas »" ECHEC
verifier_refus T17 jeton-refuse-3-fois nominal "faux_1\nfaux_2\nfaux_3\n" "trois jetons refusés" "arrêt après 3 refus, rien lancé"
verifier_refus T18 jeton-absent nominal "\n" "aucun jeton saisi" "arrêt propre, rien téléchargé"
verifier_refus T19 jeton-mal-forme nominal 'abc" X-Injection: 1\n\n' "caractères inattendus" \
  "jeton mal formé ignoré, pas d'injection d'en-tête"
grep -q "X-Injection" "$JOURNAL_REQ" && consigner T19b "injection d'en-tête" "aucune" ECHEC

: > "$JOURNAL_GH"
GH_ESSAI="$FAUX_GH" GH_CONNECTE=1 verifier_succes T20 gh-connecte nominal "" "gh connecté : installé sans jeton ni connexion" gh
detail=""
grep -q "Jeton GitHub (Entrée" "$SORTIES/gh-connecte.txt" && detail="jeton demandé"
grep -q "^auth login" "$JOURNAL_GH" && detail="$detail connexion relancée"
grep -q "^api repos/tarnaub/le-lutin-bleu/releases/assets/" "$JOURNAL_GH" || detail="$detail téléchargement hors gh"
grep -q "gh est déjà connecté" "$SORTIES/gh-connecte.txt" || detail="$detail usage de gh non dit"
bilan T20b "gh connecté : rien d'autre" "ni jeton, ni nouvelle connexion" "$detail"

: > "$JOURNAL_GH"
GH_ESSAI="$FAUX_GH" GH_CONNEXION=ok verifier_succes T21 gh-connexion-navigateur nominal "o\n" "gh non connecté, « oui » : connexion puis installation" gh
detail=""
grep -q "^auth login --hostname github.com --git-protocol https --web" "$JOURNAL_GH" || detail="connexion --web non demandée"
avant "$SORTIES/gh-connexion-navigateur.txt" "TOUS les dépôts" "Code à usage unique" || detail="$detail portée non dite avant la connexion"
bilan T21b "portée dite avant la connexion gh" "avertissement, puis gh auth login --web" "$detail"

GH_ESSAI="$FAUX_GH" verifier_succes T22 gh-refuse-puis-jeton nominal "n\n$JETON_VALIDE\n" "gh refusé : jeton" jeton
GH_ESSAI="$FAUX_GH" GH_CONNEXION=echec verifier_succes T23 gh-connexion-echouee nominal "o\n$JETON_VALIDE\n" "connexion gh échouée : jeton" jeton
GH_ESSAI="$FAUX_GH" GH_CONNECTE=1 GH_JETON="$JETON_SANS_ACCES" verifier_succes T24 gh-sans-acces nominal "$JETON_VALIDE\n" \
  "gh connecté sans accès : message puis jeton" jeton
grep -q "le compte connecté à gh ne voit pas" "$SORTIES/gh-sans-acces.txt" || consigner T24b "message gh sans accès" "dit" ECHEC
GH_ESSAI="$ESSAIS/gh-absent/gh" verifier_succes T25 gh-absent nominal "$JETON_VALIDE\n" "gh absent : jeton directement" jeton
grep -q "gh n'est pas installé" "$SORTIES/gh-absent.txt" || consigner T25b "message gh absent" "dit" ECHEC

verifier_refus T26 limite-jeton limite "$JETON_VALIDE\n" "limite pour l'instant les requêtes" "quota épuisé : message dédié, rien lancé"
grep -q "jeton refusé" "$SORTIES/limite-jeton.txt" && consigner T26b "quota : pas « jeton refusé »" "message juste" ECHEC
GH_ESSAI="$FAUX_GH" GH_CONNECTE=1 verifier_refus T27 limite-gh limite "" "limite pour l'instant les requêtes" "quota épuisé par gh : message dédié"
GH_ESSAI="$FAUX_GH" GH_CONNECTE=1 GH_API="http://127.0.0.1:$PORT_FERME" verifier_refus T28 gh-injoignable nominal "" \
  "gh n'a pas obtenu de réponse de GitHub" "gh sans réseau : message clair, rien lancé"

# --- vérifications de la release -------------------------------------------------------------------------------------

verifier_refus T29 installateur-altere installateur-altere "$JETON_VALIDE\n" "n'est pas celui que décrit le manifeste signé" \
  "refus : empreinte ≠ manifeste signé"
verifier_refus T30 manifeste-altere manifeste-altere "$JETON_VALIDE\n" "signature du manifeste" "refus : signature invalide"
verifier_refus T31 autre-cle autre-cle "$JETON_VALIDE\n" "signature du manifeste" "refus : clé inconnue"
verifier_refus T32 rejeu-autre-depot rejeu-autre-depot "$JETON_VALIDE\n" "vise autre/depot" "refus : manifeste d'un autre dépôt"
verifier_refus T33 rejeu-autre-version rejeu-autre-version "$JETON_VALIDE\n" "porte la V09.998" "refus : manifeste d'une autre version"
verifier_refus T34 format-inconnu format-inconnu "$JETON_VALIDE\n" "format de manifeste inconnu" "refus : format inconnu"
verifier_refus T34b champ-repete champ-repete "$JETON_VALIDE\n" "répète le champ sha256_installer" "refus : champ répété"
verifier_refus T35 digest-faux digest-faux "$JETON_VALIDE\n" "empreinte publiée par GitHub différente" "refus : empreinte GitHub fausse"
verifier_refus T36 non-signee non-signee "$JETON_VALIDE\n" "n'est pas encore signée (publication en cours)" \
  "refus : « pas encore signée, réessayez »"
grep -q "réessayez dans quelques minutes" "$SORTIES/non-signee.txt" || consigner T36b "non signée : réessayer" "conseil dit" ECHEC
verifier_refus T37 ancienne-version ancienne-version "$JETON_VALIDE\n" "plus ancienne que la version minimale" \
  "refus : V01.001 < $VMIN"
TAG_ATTENDU="$VMIN" verifier_succes T38 version-minimale version-minimale "$JETON_VALIDE\n" "la version minimale ($VMIN) est acceptée" jeton
verifier_refus T39 tronque-coupure tronque-coupure "$JETON_VALIDE\n" "interrompu ou refusé (code 18" "refus : coupure réseau (curl 18)"
verifier_refus T40 tronque-contenu tronque-contenu "$JETON_VALIDE\n" "n'est pas celui que décrit le manifeste signé" \
  "refus : installateur tronqué servi complet"

# --- réseau ----------------------------------------------------------------------------------------------------------

ENV_ESSAI=(-u https_proxy -u HTTPS_PROXY)
API_ESSAI="http://127.0.0.1:$PORT_FERME" verifier_refus T41 github-injoignable nominal "$JETON_VALIDE\n" "GitHub injoignable (curl, code 7)" \
  "message clair, rien lancé"
grep -q "déclarez-le d'abord (export https_proxy=" "$SORTIES/github-injoignable.txt" \
  || consigner T41b "injoignable : conseil du proxy" "dit" ECHEC
ENV_ESSAI=()
API_ESSAI="https://exemple.invalid" verifier_refus T42 api-hors-liste nominal "$JETON_VALIDE\n" "adresse d'API refusée" "refus sans appel réseau"

: > "$JOURNAL_PROXY"
ENV_ESSAI=(http_proxy="http://127.0.0.1:$PORT_PROXY")
verifier_succes T43 proxy nominal "$JETON_VALIDE\n" "par le proxy : installé" jeton
detail=""
grep -q "GET http://127.0.0.1:$PORT/repos/tarnaub/le-lutin-bleu/releases/latest Authorization=présent -> 200" "$JOURNAL_PROXY" \
  || detail="release non demandée par le proxy"
grep -q "GET http://localhost:$PORT/telechargement/2?signature=essai Authorization=absent -> 200" "$JOURNAL_PROXY" \
  || detail="$detail installateur non téléchargé par le proxy, ou jeton transmis au stockage"
bilan T43b "requêtes passées par le proxy" "API et stockage par le proxy, jeton gardé à l'API" "$detail"
ENV_ESSAI=(http_proxy="http://127.0.0.1:$PORT_FERME")
verifier_refus T44 proxy-ferme nominal "$JETON_VALIDE\n" "un proxy est déclaré" "proxy injoignable : message clair, rien lancé"
ENV_ESSAI=()

# --- amorce coupée, formes de la commande ----------------------------------------------------------------------------

# T45 : l'amorce coupée à chaque fin de ligne et en cinq points de la dernière ligne : rien ne s'exécute
lignes="$(wc -l < "$AMORCE_ESSAI" | tr -d ' ')"
taille="$(wc -c < "$AMORCE_ESSAI" | tr -d ' ')"
derniere="$(tail -n 1 "$AMORCE_ESSAI")"
debut_derniere=$((taille - ${#derniere} - 1))
lancees=0 requetes=0 coupures=0
n0="$(requetes_api)"
k=1
while [ "$k" -lt "$lignes" ]; do
  head -n "$k" "$AMORCE_ESSAI" > "$ESSAIS/tronquees/amorce-l$k.sh"
  AMORCE_LANCEE="$ESSAIS/tronquees/amorce-l$k.sh" lancer_amorce "tronquee-l$k" nominal "$JETON_VALIDE\n"
  [ ! -e "$TEMOINS/tronquee-l$k.txt" ] || lancees=$((lancees + 1))
  coupures=$((coupures + 1))
  k=$((k + 1))
done
for c in $((debut_derniere + 3)) $((debut_derniere + 8)) $((debut_derniere + 16)) $((debut_derniere + 19)) $((taille - 2)); do
  head -c "$c" "$AMORCE_ESSAI" > "$ESSAIS/tronquees/amorce-o$c.sh"
  AMORCE_LANCEE="$ESSAIS/tronquees/amorce-o$c.sh" lancer_amorce "tronquee-o$c" nominal "$JETON_VALIDE\n"
  [ ! -e "$TEMOINS/tronquee-o$c.txt" ] || lancees=$((lancees + 1))
  coupures=$((coupures + 1))
done
requetes=$(( $(requetes_api) - n0 ))
rm -f "$SORTIES"/tronquee-*.txt
if [ "$lancees" -eq 0 ] && [ "$requetes" -eq 0 ] && travail_vide; then
  consigner T45 "amorce tronquée ($coupures coupures)" "rien exécuté, aucune requête" OK
else
  consigner T45 "amorce tronquée ($coupures coupures)" "rien exécuté, aucune requête" ECHEC "($lancees lancements, $requetes requêtes)"
fi
# T45b : le seul point de coupure qui exécute quelque chose, juste après « amorce_principale » sans « "$@" » : c'est
# l'amorce entière, sans options, avec toutes ses vérifications
c=$((debut_derniere + ${#derniere} - 5))
head -c "$c" "$AMORCE_ESSAI" > "$ESSAIS/tronquees/amorce-o$c.sh"
detail=""
[ "$(tail -c 17 "$ESSAIS/tronquees/amorce-o$c.sh")" = amorce_principale ] || detail="point de coupure inattendu"
AMORCE_LANCEE="$ESSAIS/tronquees/amorce-o$c.sh" lancer_amorce tronquee-sans-arguments nominal "$JETON_VALIDE\n" --sans-lancement
controler_succes tronquee-sans-arguments jeton
grep -q -- "--sans-lancement" "$TEMOINS/tronquee-sans-arguments.txt" 2>/dev/null && DETAIL="$DETAIL options transmises"
bilan T45b "coupée juste après amorce_principale" "l'amorce entière, sans options, vérifications comprises" "$detail$DETAIL"

# T46 : démonstration du risque sans enveloppe : un script naïf coupé exécute sa première ligne
printf 'touch "%s/naif/etape-1-faite"\ntouch "%s/naif/etape-2-complete"\n' "$ESSAIS" "$ESSAIS" > "$ESSAIS/naif/script-naif.sh"
head -c $(( $(wc -c < "$ESSAIS/naif/script-naif.sh") - 10 )) "$ESSAIS/naif/script-naif.sh" > "$ESSAIS/naif/script-naif-tronque.sh"
/bin/bash "$ESSAIS/naif/script-naif-tronque.sh" > "$SORTIES/T46-naif.txt" 2>&1 || true
if [ -e "$ESSAIS/naif/etape-1-faite" ] && [ ! -e "$ESSAIS/naif/etape-2-complete" ]; then
  consigner T46 "script naïf tronqué (démonstration)" "s'exécute en partie" OK
else
  consigner T46 "script naïf tronqué (démonstration)" "s'exécute en partie" ECHEC
fi

# T47 : « télécharger puis bash » depuis l'adresse de release publique, empreinte comparée à celle publiée
publiee="$(sha "$FAUX/public/amorce-le-lutin-bleu.sh")"
detail=""
echo nominal > "$FAUX/scenario"
/usr/bin/curl -fsSLo "$ESSAIS/telecharge/amorce-le-lutin-bleu.sh" "$URL_PUBLIQUE" 2>"$SORTIES/T47-curl.txt" || detail="téléchargement échoué"
[ "$(sha "$ESSAIS/telecharge/amorce-le-lutin-bleu.sh" 2>/dev/null)" = "$publiee" ] || detail="$detail empreinte différente"
AMORCE_LANCEE="$ESSAIS/telecharge/amorce-le-lutin-bleu.sh" lancer_amorce telecharger-puis-bash nominal "$JETON_VALIDE\n"
controler_succes telecharger-puis-bash jeton
bilan T47 "télécharger puis bash" "empreinte conforme, installateur lancé" "$detail$DETAIL"

# T48 : téléchargement de l'amorce coupé : curl -f échoue ; le fichier partiel n'a pas l'empreinte publiée et, lancé
# quand même, n'exécute rien
detail=""
echo amorce-coupee > "$FAUX/scenario"
rm -f "$ESSAIS/telecharge/amorce-coupee.sh"
code=0
/usr/bin/curl -fsSLo "$ESSAIS/telecharge/amorce-coupee.sh" "$URL_PUBLIQUE" 2>"$SORTIES/T48-curl.txt" || code=$?
[ "$code" -eq 18 ] || detail="curl code $code au lieu de 18"
[ "$(sha "$ESSAIS/telecharge/amorce-coupee.sh" 2>/dev/null)" != "$publiee" ] || detail="$detail empreinte identique"
n0="$(requetes_api)"
AMORCE_LANCEE="$ESSAIS/telecharge/amorce-coupee.sh" lancer_amorce telecharge-coupe amorce-coupee "$JETON_VALIDE\n"
[ ! -e "$TEMOINS/telecharge-coupe.txt" ] || detail="$detail installateur lancé"
[ "$(requetes_api)" = "$n0" ] || detail="$detail requête envoyée"
bilan T48 "téléchargement de l'amorce coupé" "curl 18, empreinte différente, rien exécuté" "$detail"

# T49 : curl | bash coupé en route : bash exécute ce qu'il a reçu, c'est-à-dire seulement des définitions
detail=""
n0="$(requetes_api)"
rm -f "$TEMOINS/tube-coupe.txt"
/usr/bin/curl -fsSL "$URL_PUBLIQUE" 2>"$SORTIES/T49-curl.txt" \
  | env LUTIN_AMORCE_API="$API" LUTIN_AMORCE_GH="" LUTIN_AMORCE_TRAVAIL="$TRAVAIL_AMORCE" LUTIN_TEST_TEMOIN="$TEMOINS/tube-coupe.txt" \
      /bin/bash > "$SORTIES/tube-coupe.txt" 2>&1
[ ! -e "$TEMOINS/tube-coupe.txt" ] || detail="installateur lancé"
[ "$(requetes_api)" = "$n0" ] || detail="$detail requête envoyée"
grep -q "(amorce-le-lutin-bleu.sh, coupé après" "$JOURNAL_REQ" || detail="$detail coupure non jouée"
travail_vide || detail="$detail dossier de travail non nettoyé"
bilan T49 "curl | bash coupé en route" "rien exécuté, aucune requête" "$detail"

# Les deux formes dans un vrai pseudo-terminal (/usr/bin/script) : curl | bash avec gh connecté, curl | bash avec un
# jeton tapé au terminal (/dev/tty), et « bash fichier » avec un jeton tapé : la saisie ne s'affiche jamais.
pty() {  # pty NOM DELAI SAISIE GH_CONNECTE COMMANDE... : transcription dans $SORTIES/NOM.txt
  local nom="$1" delai="$2" saisie="$3" connecte="$4"
  shift 4
  rm -f "$TEMOINS/$nom.txt"
  if [ "$connecte" = 1 ]; then touch "$GH_ETAT/connecte"; else rm -f "$GH_ETAT/connecte"; fi
  { sleep "$delai"; printf '%b' "$saisie"; } | env LUTIN_AMORCE_API="$API" LUTIN_AMORCE_TRAVAIL="$TRAVAIL_AMORCE" \
      LUTIN_TEST_TEMOIN="$TEMOINS/$nom.txt" FAUX_GH_ETAT="$GH_ETAT" FAUX_GH_API="$API" FAUX_GH_JOURNAL="$JOURNAL_GH" \
      FAUX_GH_JETON="$JETON_GH" FAUX_GH_CONNEXION=echec \
      /usr/bin/script -q "$SORTIES/$nom.txt" "$@" >/dev/null 2>&1
  STATUT=0
}
echo nominal > "$FAUX/scenario"
# shellcheck disable=SC2016  # « $1 » est développé par le bash lancé dans le pseudo-terminal
TUBE='/usr/bin/curl -fsSL "$1" | /bin/bash'
pty tube-gh 0 "" 1 env LUTIN_AMORCE_GH="$FAUX_GH" /bin/bash -c "$TUBE" _ "$URL_PUBLIQUE"
controler_succes tube-gh gh
bilan T50 "curl | bash (pseudo-terminal, gh)" "installateur lancé" "$DETAIL"

pty tube-jeton 3 "$JETON_VALIDE\n" 0 env LUTIN_AMORCE_GH="" /bin/bash -c "$TUBE" _ "$URL_PUBLIQUE"
controler_succes tube-jeton jeton
grep -q "$JETON_VALIDE" "$SORTIES/tube-jeton.txt" && DETAIL="$DETAIL jeton affiché"
bilan T51 "curl | bash, jeton tapé sur /dev/tty" "saisie masquée, installateur lancé" "$DETAIL"

pty fichier-jeton 3 "$JETON_VALIDE\n" 0 env LUTIN_AMORCE_GH="" /bin/bash "$AMORCE_ESSAI"
controler_succes fichier-jeton jeton
grep -q "$JETON_VALIDE" "$SORTIES/fichier-jeton.txt" && DETAIL="$DETAIL jeton affiché"
bilan T52 "bash fichier, jeton tapé au terminal" "saisie masquée, installateur lancé" "$DETAIL"

# --- traces ----------------------------------------------------------------------------------------------------------

if grep -q "^INTERDIT" "$JOURNAL_GH"; then
  consigner T53 "faux gh : commandes employées" "auth status, auth login, api seulement" ECHEC "($(grep '^INTERDIT' "$JOURNAL_GH" | head -n 1))"
else
  consigner T53 "faux gh : commandes employées" "auth status, auth login, api seulement" OK
fi

fuites="$(grep -rlE -- "$JETON_VALIDE|$JETON_GH|$JETON_SANS_ACCES" "$SORTIES" "$TEMOINS" "$JOURNAL_REQ" "$JOURNAL_PROXY" \
  "$JOURNAL_GH" "$TRAVAIL_AMORCE" "$ESSAIS/faux-github.out" "$ESSAIS/faux-proxy.out" 2>/dev/null | tr '\n' ' ')"
bilan T54 "jetons absents des sorties et journaux" "aucune occurrence" "${fuites:+trouvés dans $fuites}"

{
  echo ""
  echo "Bilan : $REUSSIS réussis, $ECHOUES en échec, $IGNORES ignorés."
} >> "$RESULTATS"
echo "Bilan : $REUSSIS réussis, $ECHOUES en échec, $IGNORES ignorés. Détail : $RESULTATS"
[ "$ECHOUES" -eq 0 ]
