#!/bin/bash
# amorce-le-lutin-bleu.sh — amorce publique d'installation du Lutin Bleu sur un Mac.
#
# L'amorce ne contient aucun code du Lutin Bleu. Elle vérifie les prérequis, obtient l'accès au dépôt privé
# tarnaub/le-lutin-bleu (gh déjà connecté, sinon connexion gh dans le navigateur, sinon jeton GitHub saisi sans écho),
# télécharge l'installateur de la dernière release avec son manifeste signé, vérifie la signature du manifeste avec la
# clé publique embarquée ci-dessous, puis l'empreinte de l'installateur, et seulement alors le lance. Elle ne garde
# rien : ni jeton, ni fichier, rien dans le trousseau.
#
# Usage conseillé (télécharger, comparer l'empreinte à celle publiée dans le README, lire, puis lancer) :
#   curl -fsSLo amorce-le-lutin-bleu.sh https://github.com/tarnaub/le-lutin-bleu-installer/releases/latest/download/amorce-le-lutin-bleu.sh
#   shasum -a 256 amorce-le-lutin-bleu.sh
#   bash amorce-le-lutin-bleu.sh
# Usage court (exécute sans lecture préalable) :
#   curl -fsSL https://github.com/tarnaub/le-lutin-bleu-installer/releases/latest/download/amorce-le-lutin-bleu.sh | bash
#
# Tout le script tient dans des fonctions ; la seule commande est la dernière ligne : un téléchargement coupé en route
# ne lance rien. Jamais de jeton dans la commande : l'amorce le demande. Compatible bash 3.2 (macOS).

amorce_configurer() {
  AMORCE_VERSION="1.0.0"
  DEPOT="tarnaub/le-lutin-bleu"
  # La plus ancienne release acceptée, relevée à chaque publication de l'amorce : une ancienne release, même
  # correctement signée, republiée comme « dernière » est refusée.
  VERSION_MINIMALE="V01.077"
  # La même clé que app/lutin_bleu/seed/release-signing-key.pub du dépôt privé ; à changer ici à chaque rotation.
  CLE_PUBLIQUE="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILuYLtEHQV+fa6MNxO5hnKH9ABioy0LelC9ku0S9UeJR"
  ESPACE_SIGNATURE="le-lutin-bleu-release@lelutinbleu.com"
  IDENTITE_SIGNATURE="release@lelutinbleu.com"
  INSTALLATEUR="installer-le-lutin-bleu.sh"
  JETON_CLASSIQUE="https://github.com/settings/tokens/new?scopes=repo&description=Installation+du+Lutin+Bleu"
  API="${LUTIN_AMORCE_API:-https://api.github.com}"
  # shellcheck disable=SC2191  # --proto et --proto-redir prennent « =https » comme argument suivant
  case "$API" in
    https://api.github.com)
      CURL=(/usr/bin/curl -sS -L --retry 2 --connect-timeout 15 --max-time 300 --tlsv1.2 --proto =https --proto-redir =https) ;;
    http://127.0.0.1:[0-9]*)  # les tests seulement : un faux GitHub sur ce Mac
      CURL=(/usr/bin/curl -sS -L --retry 2 --connect-timeout 5 --max-time 60) ;;
    *) amorce_echec "adresse d'API refusée : $API" ;;
  esac
  if [ -n "${LUTIN_AMORCE_GH+x}" ]; then  # nommé, même vide (aucun) : jamais un autre
    GH="$LUTIN_AMORCE_GH"
  else
    GH="$(command -v gh 2>/dev/null || true)"
    [ -n "$GH" ] || { [ -x /opt/homebrew/bin/gh ] && GH=/opt/homebrew/bin/gh; }
    [ -n "$GH" ] || { [ -x /usr/local/bin/gh ] && GH=/usr/local/bin/gh; }
  fi
  TRAVAIL_PARENT="${LUTIN_AMORCE_TRAVAIL:-$HOME/Library/Caches}"
  ACCES=aucun JETON="" TRAVAIL="" TAG="" CODE="" RC=0 LIMITE=0 PORTEE_DITE=0 DIGEST_GITHUB=""
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

Aucun jeton ne se donne dans la commande : l'amorce le demande, sans l'afficher.
EOF
}

amorce_lire_options() {
  while [ $# -gt 0 ]; do
    case "$1" in
      *ghp_*|*gho_*|*ghu_*|*ghs_*|*ghr_*|*github_pat_*)
        amorce_echec "un jeton ne s'écrit jamais dans la commande (il resterait dans l'historique du Terminal) : supprimez ce jeton sur github.com, puis relancez sans lui ; l'amorce le demandera" ;;
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
  JETON=""
  if [ -n "$TRAVAIL" ] && [ -d "$TRAVAIL" ]; then rm -rf "$TRAVAIL"; fi
}

amorce_get() {  # amorce_get CHEMIN FICHIER [ACCEPT] : statut HTTP dans CODE, échec de transport dans RC, quota dans LIMITE
  local accept="${3:-application/vnd.github+json}" erreur=""
  RC=0 CODE=000 LIMITE=0
  rm -f "$TRAVAIL/entetes"
  case "$ACCES" in
    gh)
      if erreur="$(DO_NOT_TRACK=1 GH_TELEMETRY=false GH_PROMPT_DISABLED=1 \
          "$GH" api -H "Accept: $accept" "${1#/}" 2>&1 >"$2" </dev/null)"; then
        CODE=200
        return 0
      fi
      case "$erreur" in
        *"(HTTP "[0-9][0-9][0-9]")"*) CODE="${erreur##*(HTTP }"; CODE="${CODE%%)*}" ;;
        *) RC=1 ;;  # aucune réponse de GitHub
      esac
      case "$erreur" in *"rate limit"*) LIMITE=1 ;; esac ;;
    jeton)  # par un tuyau, jamais sur une ligne de commande que ps montrerait
      CODE="$(printf 'header = "Authorization: Bearer %s"\n' "$JETON" \
        | "${CURL[@]}" -K - -D "$TRAVAIL/entetes" -H "Accept: $accept" -H "X-GitHub-Api-Version: 2022-11-28" \
            -o "$2" -w '%{http_code}' "$API$1")" || RC=$?
      if [ "$CODE" = 403 ] && grep -qi '^x-ratelimit-remaining: *0' "$TRAVAIL/entetes" 2>/dev/null; then LIMITE=1; fi ;;
    *) amorce_echec "aucun accès au dépôt n'est établi" ;;
  esac
  [ "$CODE" != 429 ] || LIMITE=1
  case "$CODE" in [0-9][0-9][0-9]) ;; *) CODE=000 ;; esac
}

amorce_proxy_declare() {
  [ -n "${https_proxy:-}${HTTPS_PROXY:-}${http_proxy:-}${ALL_PROXY:-}${all_proxy:-}" ]
}

amorce_echec_reseau() {  # amorce_echec_reseau : RC venu de curl, ou 1 pour gh
  local proxy="derrière un proxy d'entreprise, déclarez-le d'abord (export https_proxy=http://proxy:port)"
  amorce_proxy_declare && proxy="un proxy est déclaré (variable https_proxy ou voisine) : vérifiez son adresse"
  if [ "$ACCES" = gh ]; then
    amorce_echec "gh n'a pas obtenu de réponse de GitHub : vérifiez le réseau ; $proxy. Rien n'a été lancé"
  fi
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
    || amorce_echec "GitHub limite pour l'instant les requêtes de ce compte (réponse $CODE) : réessayez dans une heure. Rien n'a été lancé"
  return 1
}

amorce_champ() { /usr/bin/plutil -extract "$1" raw -o - "$2" 2>/dev/null; }

amorce_gh_present() { [ -n "$GH" ] && [ -x "$GH" ]; }

amorce_gh_connecte() {
  amorce_gh_present && DO_NOT_TRACK=1 GH_TELEMETRY=false GH_PROMPT_DISABLED=1 \
    "$GH" auth status --hostname github.com >/dev/null 2>&1 </dev/null
}

amorce_oui_non() {
  local reponse=""
  printf '%s [O/n] ' "$1"
  IFS= read -r reponse <"$IN" || reponse=""
  case "$reponse" in ""|o|O|oui|Oui|OUI|y|Y|yes) return 0 ;; *) return 1 ;; esac
}

amorce_dire_portee() {  # avant toute connexion, une seule fois
  [ "$PORTEE_DITE" -eq 0 ] || return 0
  PORTEE_DITE=1
  dire ""
  dire "Accès au dépôt privé $DEPOT : à lire avant de vous connecter."
  dire "  • Ce dépôt appartient à un compte GitHub personnel. GitHub n'y permet ni un accès en lecture seule, ni un"
  dire "    jeton « à grain fin » limité à ce seul dépôt."
  dire "  • La connexion gh (portées « repo », « read:org », « gist ») comme un jeton classique « repo » ouvrent, en"
  dire "    lecture ET en écriture, TOUS les dépôts auxquels votre compte GitHub a accès, y compris ceux de votre"
  dire "    employeur si votre compte est membre de son organisation GitHub."
  dire "  • Si vous choisissez le jeton : un jeton classique, la seule case « repo », la durée la plus courte (7 jours) ;"
  dire "    supprimez-le après l'installation."
  dire "  • L'amorce ne garde rien : ni jeton, ni fichier, rien dans le trousseau. La connexion gh, elle, reste dans le"
  dire "    trousseau comme pour tout usage de gh, jusqu'à « gh auth logout »."
  dire "  Utilisez votre propre compte GitHub, invité sur le dépôt : jamais le jeton de quelqu'un d'autre."
  dire ""
}

amorce_lire_jeton() {  # 0 : un jeton lisible dans JETON ; 1 : abandon ; 2 : jeton illisible
  dire "Jeton classique de VOTRE compte GitHub, portée « repo », 7 jours :"
  dire "  $JETON_CLASSIQUE"
  dire "  Il ne s'affiche pas pendant la frappe, ne s'écrit nulle part et est oublié à la fin de l'installation."
  printf 'Jeton GitHub (Entrée pour abandonner) : '
  IFS= read -rs JETON <"$IN" || JETON=""
  printf '\n'
  [ -n "$JETON" ] || return 1
  case "$JETON" in *[!A-Za-z0-9_]*) JETON=""; return 2 ;; esac
  return 0
}

amorce_motif_refus() {  # le refus d'un jeton, selon la réponse de GitHub
  case "$CODE" in
    401) printf 'jeton refusé par GitHub (expiré, supprimé ou mal copié)' ;;
    404) printf "ce compte ne voit pas %s (case « repo » non cochée, ou invitation pas encore acceptée)" "$DEPOT" ;;
    *) printf 'accès refusé par GitHub (réponse %s)' "$CODE" ;;
  esac
}

amorce_obtenir_release() {
  local essais=0 lu=0
  if amorce_gh_connecte; then
    ACCES=gh
    dire "• gh est déjà connecté sur ce Mac : l'amorce s'en sert pour lire le dépôt, sans rien changer à cette connexion."
    amorce_get "/repos/$DEPOT/releases/latest" "$TRAVAIL/release.json"
    amorce_reponse_ok && return 0
    avertir "le compte connecté à gh ne voit pas $DEPOT (invitation pas encore acceptée, ou autre compte) : accès par jeton"
    ACCES=aucun
  fi
  amorce_dire_portee
  if [ "$ACCES" = aucun ] && amorce_gh_present && ! amorce_gh_connecte; then
    if amorce_oui_non "Se connecter à GitHub avec gh, dans le navigateur ?"; then
      DO_NOT_TRACK=1 GH_TELEMETRY=false "$GH" auth login --hostname github.com --git-protocol https --web <"$IN" \
        || avertir "connexion gh non aboutie"
      if amorce_gh_connecte; then
        ACCES=gh
        amorce_get "/repos/$DEPOT/releases/latest" "$TRAVAIL/release.json"
        amorce_reponse_ok && return 0
        avertir "gh est connecté, mais ce compte ne voit pas $DEPOT : demandez une invitation à l'auteur, ou utilisez un jeton"
        ACCES=aucun
      fi
    fi
  elif ! amorce_gh_present; then
    dire "gh n'est pas installé sur ce Mac : l'accès passe par un jeton."
  fi
  while [ "$essais" -lt 3 ]; do
    essais=$((essais + 1))
    lu=0
    amorce_lire_jeton || lu=$?
    [ "$lu" -ne 1 ] || amorce_echec "aucun jeton saisi : rien n'a été téléchargé ni lancé"
    if [ "$lu" -eq 2 ]; then
      avertir "ce jeton contient des caractères inattendus : il est ignoré"
      continue
    fi
    ACCES=jeton
    amorce_get "/repos/$DEPOT/releases/latest" "$TRAVAIL/release.json"
    amorce_reponse_ok && return 0
    avertir "$(amorce_motif_refus)"
    JETON=""
  done
  amorce_echec "trois jetons refusés : rien n'a été téléchargé ni lancé"
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
  if [ "$ACCES" = jeton ]; then  # le jeton passe par le descripteur 3, un tuyau : ni disque, ni argument
    exec 4< <(printf '%s\n' "$JETON")
    JETON=""
    LUTIN_BLEU_JETON_FD=3 /bin/bash "$TRAVAIL/$INSTALLATEUR" --source github --version "$TAG" --depot "$DEPOT" \
      --cle-publique "$CLE_PUBLIQUE" ${OPTIONS[@]+"${OPTIONS[@]}"} <"$IN" 3<&4 4<&- || statut=$?
    exec 4<&-
  else
    /bin/bash "$TRAVAIL/$INSTALLATEUR" --source github --version "$TAG" --depot "$DEPOT" \
      --cle-publique "$CLE_PUBLIQUE" ${OPTIONS[@]+"${OPTIONS[@]}"} <"$IN" 3<&- 4<&- || statut=$?
  fi
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
