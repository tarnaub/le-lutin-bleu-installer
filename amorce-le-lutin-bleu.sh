#!/bin/bash
# amorce-le-lutin-bleu.sh — amorce publique d'installation du Lutin Bleu sur un Mac.
#
# L'amorce ne contient aucun code du Lutin Bleu. Elle vérifie les prérequis, demande sans écho la clé d'installation
# fournie par l'auteur (lecture seule de tarnaub/le-lutin-bleu et de tarnaub/le-lutin-bleu-installer), la vérifie sur
# ces deux dépôts, télécharge l'installateur de la dernière release avec son manifeste signé, vérifie la signature du
# manifeste avec la clé publique embarquée ci-dessous, puis l'empreinte de l'installateur, et seulement alors le lance,
# en lui passant la clé par un tuyau. gh n'est jamais lancé. L'amorce n'écrit ni la clé ni rien d'autre : c'est
# l'installateur vérifié qui range la clé dans le trousseau du Mac, pour les mises à jour.
#
# Usage conseillé (télécharger, comparer l'empreinte à celle publiée dans le README, lire, puis lancer) :
#   curl -fsSLo amorce-le-lutin-bleu.sh https://github.com/tarnaub/le-lutin-bleu-installer/releases/latest/download/amorce-le-lutin-bleu.sh
#   shasum -a 256 amorce-le-lutin-bleu.sh
#   bash amorce-le-lutin-bleu.sh
# Usage court (exécute sans lecture préalable) :
#   curl -fsSL https://github.com/tarnaub/le-lutin-bleu-installer/releases/latest/download/amorce-le-lutin-bleu.sh | bash
#
# Tout le script tient dans des fonctions ; la seule commande est la dernière ligne : un téléchargement coupé en route
# ne lance rien. Jamais de clé dans la commande : l'amorce la demande. Compatible bash 3.2 (macOS).

amorce_configurer() {
  AMORCE_VERSION="1.1.0"
  DEPOT="tarnaub/le-lutin-bleu"
  DEPOT_AMORCE="tarnaub/le-lutin-bleu-installer"
  # La plus ancienne release acceptée, relevée à chaque publication de l'amorce : une ancienne release, même
  # correctement signée, republiée comme « dernière » est refusée. Celle-ci est la première dont l'installateur range
  # la clé d'installation au trousseau : une plus ancienne laisserait le Mac sans mises à jour.
  VERSION_MINIMALE="V01.144"
  # La même clé que app/lutin_bleu/seed/release-signing-key.pub du dépôt privé ; à changer ici à chaque rotation.
  CLE_PUBLIQUE="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILuYLtEHQV+fa6MNxO5hnKH9ABioy0LelC9ku0S9UeJR"
  ESPACE_SIGNATURE="le-lutin-bleu-release@lelutinbleu.com"
  IDENTITE_SIGNATURE="release@lelutinbleu.com"
  INSTALLATEUR="installer-le-lutin-bleu.sh"
  API="${LUTIN_AMORCE_API:-https://api.github.com}"
  # shellcheck disable=SC2191  # --proto et --proto-redir prennent « =https » comme argument suivant
  case "$API" in
    https://api.github.com)
      CURL=(/usr/bin/curl -sS -L --retry 2 --connect-timeout 15 --max-time 300 --tlsv1.2 --proto =https --proto-redir =https) ;;
    http://127.0.0.1:[0-9]*)  # les tests seulement : un faux GitHub sur ce Mac
      CURL=(/usr/bin/curl -sS -L --retry 2 --connect-timeout 5 --max-time 60) ;;
    *) amorce_echec "adresse d'API refusée : $API" ;;
  esac
  TRAVAIL_PARENT="${LUTIN_AMORCE_TRAVAIL:-$HOME/Library/Caches}"
  CLE="" TRAVAIL="" TAG="" CODE="" RC=0 LIMITE=0 DIGEST_GITHUB=""
  OPTIONS=()
  # Lu par curl | bash, le script occupe l'entrée standard : les réponses viennent alors du terminal.
  SCRIPT="${BASH_SOURCE[0]:-}"
  if [ -t 0 ] || { [ -n "$SCRIPT" ] && [ -f "$SCRIPT" ]; }; then IN=/dev/stdin; else IN=/dev/tty; fi
}

dire() { printf '%s\n' "$*"; }
avertir() { printf '  ! %s\n' "$*" >&2; }
amorce_echec() { printf 'Amorce arrêtée : %s\n' "$*" >&2; exit 1; }

amorce_aide() {
  cat <<EOF
Amorce d'installation du Lutin Bleu ($AMORCE_VERSION).

  bash amorce-le-lutin-bleu.sh [options]

  --dossier DOSSIER     où installer (défaut de l'installateur : ~/Documents/LeLutinBleu)
  --sans-lancement      ne lance pas le Lutin Bleu à la fin
  --sans-restauration   ne propose pas de restaurer d'anciennes conversations
  --restaurer           restaure toutes les anciennes conversations
  --aide                cette aide

La clé d'installation ne se donne pas dans la commande : l'amorce la demande, sans l'afficher.
EOF
}

amorce_lire_options() {
  while [ $# -gt 0 ]; do
    case "$1" in
      *ghp_*|*gho_*|*ghu_*|*ghs_*|*ghr_*|*github_pat_*)
        amorce_echec "une clé ne s'écrit jamais dans la commande (elle resterait dans l'historique du Terminal) : relancez sans elle, l'amorce la demandera ; si d'autres ont pu la voir, prévenez l'auteur" ;;
      --dossier)
        [ $# -ge 2 ] || amorce_echec "--dossier attend un dossier"
        OPTIONS+=("$1" "$2"); shift 2 ;;
      --sans-lancement|--sans-restauration|--restaurer) OPTIONS+=("$1"); shift ;;
      -h|--aide|--help) amorce_aide; exit 0 ;;
      *) amorce_echec "option inconnue : $1 (voir --aide)" ;;
    esac
  done
}

amorce_prerequis() {
  local version majeur outil
  [ "$(uname -s)" = Darwin ] || amorce_echec "le Lutin Bleu ne fonctionne que sur un Mac"
  [ "$(id -u)" != 0 ] || amorce_echec "ne lancez pas l'amorce avec sudo : tout s'installe dans votre dossier personnel"
  version="$(sw_vers -productVersion 2>/dev/null || true)"
  majeur="${version%%.*}"
  case "$majeur" in ""|*[!0-9]*) majeur=0 ;; esac
  [ "$majeur" -ge 12 ] || amorce_echec "macOS 12 ou plus récent requis (ce Mac : ${version:-inconnu})"
  for outil in /bin/bash /usr/bin/curl /usr/bin/ssh-keygen /usr/bin/shasum /usr/bin/plutil; do
    [ -x "$outil" ] || amorce_echec "$outil manque : ce Mac ne peut pas vérifier l'installateur"
  done
  # python3 n'est pas appelé ici : sans les outils d'Apple, /usr/bin/python3 ouvrirait une fenêtre d'installation.
  xcode-select -p >/dev/null 2>&1 \
    || avertir "les outils en ligne de commande d'Apple manquent : l'installateur proposera de les installer (python3 en dépend)"
  [ "$IN" != /dev/tty ] || [ -r /dev/tty ] || amorce_echec "aucun terminal pour répondre aux questions : lancez l'amorce depuis Terminal"
}

amorce_preparer_travail() {
  mkdir -p "$TRAVAIL_PARENT" || amorce_echec "impossible de préparer $TRAVAIL_PARENT"
  TRAVAIL="$(mktemp -d "$TRAVAIL_PARENT/lutin-bleu-amorce.XXXXXX")" || amorce_echec "dossier de travail impossible"
  chmod 700 "$TRAVAIL"
}

amorce_nettoyer() {
  CLE=""
  if [ -n "$TRAVAIL" ] && [ -d "$TRAVAIL" ]; then rm -rf "$TRAVAIL"; fi
}

amorce_get() {  # amorce_get CHEMIN FICHIER [ACCEPT] : statut HTTP dans CODE, échec de transport dans RC, quota dans LIMITE
  local accept="${3:-application/vnd.github+json}"
  RC=0 CODE=000 LIMITE=0
  [ -n "$CLE" ] || amorce_echec "aucune clé d'installation n'est saisie"
  rm -f "$TRAVAIL/entetes"
  # la clé par un tuyau, jamais sur une ligne de commande que ps montrerait
  CODE="$(printf 'header = "Authorization: Bearer %s"\n' "$CLE" \
    | "${CURL[@]}" -K - -D "$TRAVAIL/entetes" -H "Accept: $accept" -H "X-GitHub-Api-Version: 2022-11-28" \
        -o "$2" -w '%{http_code}' "$API$1")" || RC=$?
  if [ "$CODE" = 403 ] && grep -qi '^x-ratelimit-remaining: *0' "$TRAVAIL/entetes" 2>/dev/null; then LIMITE=1; fi
  [ "$CODE" != 429 ] || LIMITE=1
  case "$CODE" in [0-9][0-9][0-9]) ;; *) CODE=000 ;; esac
}

amorce_proxy_declare() {
  [ -n "${https_proxy:-}${HTTPS_PROXY:-}${http_proxy:-}${ALL_PROXY:-}${all_proxy:-}" ]
}

amorce_echec_reseau() {  # amorce_echec_reseau : RC venu de curl
  local proxy="derrière un proxy d'entreprise, déclarez-le d'abord (export https_proxy=http://proxy:port)"
  amorce_proxy_declare && proxy="un proxy est déclaré (variable https_proxy ou voisine) : vérifiez son adresse"
  case "$RC" in
    5) amorce_echec "proxy introuvable (curl, code 5) : vérifiez la variable https_proxy. Rien n'a été lancé" ;;
    35|51|58|60|77|83|90|91)
      amorce_echec "connexion chiffrée à GitHub refusée (curl, code $RC) : un proxy d'entreprise qui inspecte le trafic chiffré ? Voyez avec votre informatique. Rien n'a été lancé" ;;
    *) amorce_echec "GitHub injoignable (curl, code $RC) : vérifiez le réseau ; $proxy. Rien n'a été lancé" ;;
  esac
}

amorce_reponse_ok() {  # 0 : réponse 200 ; 1 : accès refusé ; arrêt sur une panne réseau ou une limite de requêtes
  [ "$RC" -eq 0 ] || amorce_echec_reseau
  [ "$CODE" != 200 ] || return 0
  [ "$LIMITE" -eq 0 ] \
    || amorce_echec "GitHub limite pour l'instant les requêtes de la clé d'installation (réponse $CODE) : réessayez dans une heure. Rien n'a été lancé"
  return 1
}

amorce_champ() { /usr/bin/plutil -extract "$1" raw -o - "$2" 2>/dev/null; }

amorce_dire_gh() {  # gh n'est jamais lancé, même connecté : sa seule présence est dite
  local chemin
  for chemin in "$(command -v gh 2>/dev/null || true)" /opt/homebrew/bin/gh /usr/local/bin/gh; do
    if [ -n "$chemin" ] && [ -x "$chemin" ]; then
      dire "• gh est installé sur ce Mac : l'amorce ne s'en sert pas, l'accès passe par la clé d'installation seule."
      return 0
    fi
  done
}

amorce_dire_cle() {  # avant la saisie, une seule fois
  dire ""
  dire "Clé d'installation : l'auteur du Lutin Bleu vous la transmet lui-même, hors de GitHub."
  dire "  • Elle ouvre en lecture seule les deux dépôts des versions, $DEPOT et $DEPOT_AMORCE, et rien d'autre."
  dire "  • Elle ne s'affiche pas pendant la frappe et ne passe jamais sur une ligne de commande. L'amorce ne l'écrit"
  dire "    nulle part : l'installateur, une fois vérifié, la range dans le trousseau du Mac (élément le-lutin-bleu,"
  dire "    compte depot-mises-a-jour), pour les mises à jour."
  dire "  • Pour la retirer ensuite : Compte et réglages › Mises à jour › Retirer la clé, dans le Lutin Bleu, ou"
  dire "    l'app Trousseau d'accès."
  dire "  Ne la collez jamais dans une commande, un message ou un fichier."
  dire ""
}

amorce_lire_cle() {  # 0 : une clé lisible dans CLE ; 1 : abandon ; 2 : caractères inattendus ; 3 : pas une clé d'installation
  printf "Clé d'installation (Entrée pour abandonner) : "
  IFS= read -rs CLE <"$IN" || CLE=""
  printf '\n'
  [ -n "$CLE" ] || return 1
  case "$CLE" in *[!A-Za-z0-9_]*) CLE=""; return 2 ;; esac
  case "$CLE" in github_pat_?*) ;; *) CLE=""; return 3 ;; esac
  return 0
}

amorce_motif_refus() {  # amorce_motif_refus DEPOT : le refus de la clé, selon la réponse de GitHub
  case "$CODE" in
    401) printf "clé d'installation refusée par GitHub (révoquée, expirée ou mal copiée) : demandez la nouvelle à l'auteur" ;;
    404) printf "la clé n'ouvre pas %s : demandez à l'auteur la clé d'installation à jour" "$1" ;;
    *) printf 'accès à %s refusé par GitHub (réponse %s)' "$1" "$CODE" ;;
  esac
}

amorce_verifier_cle() {  # 0 : la clé ouvre les deux dépôts, puis la dernière release ; 1 : refusée, motif dit
  local depot
  for depot in "$DEPOT" "$DEPOT_AMORCE"; do
    amorce_get "/repos/$depot" "$TRAVAIL/depot.json"
    amorce_reponse_ok || { avertir "$(amorce_motif_refus "$depot")"; return 1; }
  done
  amorce_get "/repos/$DEPOT/releases/latest" "$TRAVAIL/release.json"
  amorce_reponse_ok && return 0
  avertir "$(amorce_motif_refus "$DEPOT")"
  return 1
}

amorce_obtenir_release() {
  local essais=0 lu=0
  amorce_dire_gh
  amorce_dire_cle
  while [ "$essais" -lt 3 ]; do
    essais=$((essais + 1))
    lu=0
    amorce_lire_cle || lu=$?
    case "$lu" in
      1) amorce_echec "aucune clé d'installation saisie : rien n'a été téléchargé ni lancé" ;;
      2) avertir "cette clé contient des caractères inattendus : elle est ignorée"; continue ;;
      3) avertir "ce n'est pas une clé d'installation (elle commence par github_pat_) : un jeton classique n'est pas accepté"
         continue ;;
    esac
    amorce_verifier_cle && return 0
    CLE=""
  done
  amorce_echec "trois clés refusées : rien n'a été téléchargé ni lancé"
}

amorce_plus_ancienne() {  # amorce_plus_ancienne V01.050 V01.069 : la première précède la seconde
  local a="${1#V}" b="${2#V}"
  [ $((10#${a%%.*})) -lt $((10#${b%%.*})) ] && return 0
  [ $((10#${a%%.*})) -eq $((10#${b%%.*})) ] && [ $((10#${a#*.})) -lt $((10#${b#*.})) ]
}

amorce_adresse_sure() {  # l'adresse d'un fichier de la release, sur l'API du dépôt et rien d'autre
  local id="${1#"$API/repos/$DEPOT/releases/assets/"}"
  [ "$id" != "$1" ] || return 1
  case "$id" in ""|*[!0-9]*) return 1 ;; esac
}

amorce_telecharger() {
  local n i nom url u_inst="" u_man="" u_sig="" fichier
  TAG="$(amorce_champ tag_name "$TRAVAIL/release.json")" || amorce_echec "réponse de GitHub illisible"
  case "$TAG" in V[0-9][0-9].[0-9][0-9][0-9]) ;; *) amorce_echec "version de la dernière release illisible" ;; esac
  if amorce_plus_ancienne "$TAG" "$VERSION_MINIMALE"; then
    amorce_echec "la dernière release ($TAG) est plus ancienne que la version minimale de cette amorce (${VERSION_MINIMALE}) : retour en arrière refusé, rien n'est lancé. Prévenez l'auteur"
  fi
  n="$(amorce_champ assets "$TRAVAIL/release.json")" || n=0
  case "$n" in ""|*[!0-9]*) n=0 ;; esac
  i=0
  while [ "$i" -lt "$n" ]; do
    nom="$(amorce_champ "assets.$i.name" "$TRAVAIL/release.json")"
    url="$(amorce_champ "assets.$i.url" "$TRAVAIL/release.json")"
    case "$nom" in
      "$INSTALLATEUR") u_inst="$url"; DIGEST_GITHUB="$(amorce_champ "assets.$i.digest" "$TRAVAIL/release.json" || true)" ;;
      release-manifest.txt) u_man="$url" ;;
      release-manifest.txt.sig) u_sig="$url" ;;
    esac
    i=$((i + 1))
  done
  [ -n "$u_inst" ] || amorce_echec "la release $TAG n'a pas d'installateur"
  [ -n "$u_man" ] && [ -n "$u_sig" ] \
    || amorce_echec "la release $TAG n'est pas encore signée (publication en cours) : rien n'est lancé ; réessayez dans quelques minutes, ou plus tard"
  dire "• Téléchargement de l'installateur de la $TAG et de sa signature…"
  for fichier in "$INSTALLATEUR:$u_inst" "release-manifest.txt:$u_man" "release-manifest.txt.sig:$u_sig"; do
    nom="${fichier%%:*}" url="${fichier#*:}"
    amorce_adresse_sure "$url" || amorce_echec "adresse inattendue pour $nom : rien n'est lancé"
    amorce_get "${url#"$API"}" "$TRAVAIL/$nom" application/octet-stream
    if [ "$RC" -ne 0 ] || [ "$CODE" != 200 ]; then
      amorce_echec "téléchargement de $nom interrompu ou refusé (code $RC, réponse $CODE) : rien n'est lancé"
    fi
  done
}

amorce_verifier() {
  local m_format m_tag m_depot m_inst m_double reel
  printf '%s namespaces="%s" %s\n' "$IDENTITE_SIGNATURE" "$ESPACE_SIGNATURE" "$CLE_PUBLIQUE" > "$TRAVAIL/allowed_signers"
  /usr/bin/ssh-keygen -Y verify -f "$TRAVAIL/allowed_signers" -I "$IDENTITE_SIGNATURE" -n "$ESPACE_SIGNATURE" \
    -s "$TRAVAIL/release-manifest.txt.sig" < "$TRAVAIL/release-manifest.txt" >/dev/null 2>&1 \
    || amorce_echec "signature du manifeste de la $TAG refusée (clé inconnue ou contenu modifié) : l'installateur n'est pas lancé"
  # un champ écrit deux fois serait lu ici le premier, par le Lutin Bleu le dernier : refusé
  m_double="$(awk -F= 'NF > 1 { k = $1; gsub(/^[ \t]+|[ \t]+$/, "", k); print k }' "$TRAVAIL/release-manifest.txt" | sort | uniq -d | head -n 1)"
  [ -z "$m_double" ] || amorce_echec "le manifeste signé répète le champ $m_double : l'installateur n'est pas lancé"
  m_format="$(sed -n 's/^format=//p' "$TRAVAIL/release-manifest.txt" | head -n 1)"
  m_tag="$(sed -n 's/^tag=//p' "$TRAVAIL/release-manifest.txt" | head -n 1)"
  m_depot="$(sed -n 's/^repository=//p' "$TRAVAIL/release-manifest.txt" | head -n 1)"
  m_inst="$(sed -n 's/^sha256_installer=//p' "$TRAVAIL/release-manifest.txt" | head -n 1)"
  [ "$m_format" = lutin-bleu-release-v1 ] || amorce_echec "format de manifeste inconnu : l'installateur n'est pas lancé"
  [ "$m_tag" = "$TAG" ] || amorce_echec "le manifeste signé porte la $m_tag, pas la $TAG : l'installateur n'est pas lancé"
  [ "$m_depot" = "$DEPOT" ] || amorce_echec "le manifeste signé vise $m_depot, pas $DEPOT : l'installateur n'est pas lancé"
  reel="$(/usr/bin/shasum -a 256 "$TRAVAIL/$INSTALLATEUR" | cut -d' ' -f1)"
  [ "$reel" = "$m_inst" ] \
    || amorce_echec "l'installateur téléchargé ($reel) n'est pas celui que décrit le manifeste signé ($m_inst) : il n'est pas lancé"
  case "$DIGEST_GITHUB" in
    sha256:*) [ "${DIGEST_GITHUB#sha256:}" = "$reel" ] || amorce_echec "empreinte publiée par GitHub différente : l'installateur n'est pas lancé" ;;
  esac
  dire "  Signature vérifiée : installateur de la $TAG, empreinte SHA-256 $reel."
}

amorce_lancer() {
  local statut=0
  dire "• Lancement de l'installateur de la ${TAG}…"
  # la clé passe par le descripteur 3, un tuyau : ni disque, ni argument ; LUTIN_BLEU_CLE_SEULE : l'installateur ne
  # retombe jamais sur gh ni sur une autre saisie
  exec 4< <(printf '%s\n' "$CLE")
  CLE=""
  LUTIN_BLEU_CLE_SEULE=1 LUTIN_BLEU_JETON_FD=3 /bin/bash "$TRAVAIL/$INSTALLATEUR" --source github --version "$TAG" \
    --depot "$DEPOT" --cle-publique "$CLE_PUBLIQUE" ${OPTIONS[@]+"${OPTIONS[@]}"} <"$IN" 3<&4 4<&- || statut=$?
  exec 4<&-
  return "$statut"
}

amorce_principale() {
  set -u
  set -o pipefail
  amorce_configurer
  trap amorce_nettoyer EXIT
  amorce_lire_options "$@"
  dire "Amorce d'installation du Lutin Bleu ($AMORCE_VERSION) — dépôt $DEPOT"
  amorce_prerequis
  amorce_preparer_travail
  amorce_obtenir_release
  amorce_telecharger
  amorce_verifier
  amorce_lancer
}

amorce_principale "$@"
