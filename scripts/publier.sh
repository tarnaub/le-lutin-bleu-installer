#!/bin/bash
# publier.sh — publie l'amorce comme fichier d'une release du dépôt public tarnaub/le-lutin-bleu-installer.
#
# À lancer par l'auteur, ou par un agent après son feu vert (décision du 07/11/2026), depuis une copie à jour de ce
# dépôt, après avoir :
#   1. créé le dépôt tarnaub/le-lutin-bleu-installer, l'avoir déclaré en origin, et activé les releases immuables
#      (Settings › General › Releases) ;
#   2. vérifié AMORCE_VERSION et VERSION_MINIMALE dans l'amorce (VERSION_MINIMALE est posée par l'agent de fusion de
#      la version du dépôt principal qui la relève), l'empreinte et l'adresse figée du README, le tout commité sur main.
#
#   scripts/publier.sh [--essai] [--cle-reference CHEMIN] [--immuables-verifiees] [--prive]
#
# --prive : publie dans le dépôt encore privé (l'auteur le rendra public lui-même). L'amorce n'est alors pas
# téléchargeable sans authentification : la vérification finale passe par gh, et le message aux personnes invitées attend
# que le dépôt soit public. Sans --prive, un dépôt privé est refusé.
#
# Dans l'ordre :
#   - vérifie la branche main, l'absence de modification non commitée, la version de l'amorce et son étiquette ;
#   - lance les tests (tests/lancer-tests.sh), dont l'égalité de la clé embarquée avec celle du dépôt privé ;
#   - calcule l'empreinte SHA-256 de l'amorce et vérifie qu'elle figure dans le README, avec l'adresse figée ;
#   - s'arrête là avec --essai : rien ne part sur le réseau ;
#   - vérifie gh connecté, origin, le dépôt public, les releases immuables (--immuables-verifiees si l'API ne répond pas
#     et que le réglage a été vérifié à la main), l'absence de release pour cette étiquette ;
#   - pousse main et l'étiquette vX.Y.Z, crée la release en brouillon avec l'amorce, compare l'empreinte que GitHub
#     publie, puis publie la release (elle devient alors immuable) ;
#   - retélécharge l'amorce sans authentification par ses deux adresses (figée et « latest ») et compare l'empreinte ;
#   - affiche le message à envoyer hors de GitHub aux personnes invitées, avec l'empreinte.
set -euo pipefail
cd "$(dirname "$0")/.."
DEPOT_PUBLIC="tarnaub/le-lutin-bleu-installer"
AMORCE="amorce-le-lutin-bleu.sh"
GH="$(command -v gh || echo /opt/homebrew/bin/gh)"
CLE_REF="../le-lutin-bleu/app/lutin_bleu/seed/release-signing-key.pub"
ESSAI=0 IMMUABLES_VERIFIEES=0 PRIVE=0

fail() { echo "Publication impossible : $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --essai) ESSAI=1; shift ;;
    --immuables-verifiees) IMMUABLES_VERIFIEES=1; shift ;;
    --prive) PRIVE=1; shift ;;
    --cle-reference)
      [[ $# -ge 2 ]] || fail "--cle-reference attend le chemin de seed/release-signing-key.pub"
      CLE_REF="$2"; shift 2 ;;
    *) fail "option inconnue : $1 (attendu : [--essai] [--cle-reference CHEMIN] [--immuables-verifiees] [--prive])" ;;
  esac
done

# --- vérifications locales -------------------------------------------------------------------------------------------

version="$(sed -n 's/^  AMORCE_VERSION="\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)"$/\1/p' "$AMORCE")"
[[ -n "$version" ]] || fail "AMORCE_VERSION illisible dans $AMORCE"
tag="v$version"
vmin="$(sed -n 's/^  VERSION_MINIMALE="\(V[0-9][0-9]\.[0-9][0-9][0-9]\)"$/\1/p' "$AMORCE")"
[[ -n "$vmin" ]] || fail "VERSION_MINIMALE illisible dans $AMORCE"
if grep -q "MARQUEUR FUSION J" "$AMORCE"; then
  fail "VERSION_MINIMALE porte encore le marqueur de fusion du lot J : c'est à l'agent de fusion de la version du dépôt principal qui publie le patch de J de la remplacer par ce numéro et de retirer le marqueur ; puis, dans cet ordre : reporter la nouvelle empreinte de l'amorce dans les deux README, rejouer les tests, commiter"
fi
cle="$(sed -n 's/^  CLE_PUBLIQUE="\(.*\)"$/\1/p' "$AMORCE")"
[[ "$(git rev-parse --abbrev-ref HEAD)" == main ]] || fail "la branche courante n'est pas main"
[[ -z "$(git status --porcelain)" ]] || fail "des modifications ne sont pas commitées"$'\n'"$(git status --short)"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  [[ "$(git rev-list -n 1 "$tag")" == "$(git rev-parse HEAD)" ]] || fail "l'étiquette $tag existe déjà sur un autre commit"
fi
[[ -f "$CLE_REF" ]] || fail "clé publique du dépôt privé introuvable : $CLE_REF (--cle-reference CHEMIN)"

echo "Tests de l'amorce…"
LUTIN_CLE_REFERENCE="$CLE_REF" /bin/bash tests/lancer-tests.sh || fail "tests en échec (tests/.essais/resultats.md)"
grep -q '^| T06 |.*| réussi |$' tests/.essais/resultats.md \
  || fail "la clé embarquée n'a pas été comparée à celle du dépôt privé, ou diffère"
grep -q '^| T05 |.*| réussi |$' tests/.essais/resultats.md \
  || fail "les noms internes ou personnels n'ont pas été contrôlés (liste locale .termes-internes absente), ou sont présents"

empreinte="$(shasum -a 256 "$AMORCE" | cut -d' ' -f1)"
fixe="https://github.com/$DEPOT_PUBLIC/releases/download/$tag/$AMORCE"
derniere="https://github.com/$DEPOT_PUBLIC/releases/latest/download/$AMORCE"
grep -q "$empreinte" README.md || fail "le README ne donne pas l'empreinte de l'amorce ($empreinte)"
grep -qF "$fixe" README.md || fail "le README ne donne pas l'adresse figée $fixe"

cat <<EOF

Amorce prête à publier
  version            : $tag
  version minimale   : $vmin (les releases plus anciennes du Lutin Bleu sont refusées)
  clé publique       : $cle
  empreinte SHA-256  : $empreinte
  adresse figée      : $fixe
EOF
[[ "$PRIVE" -eq 1 ]] && echo "  dépôt              : privé accepté (--prive) ; téléchargement anonyme seulement une fois public"
if [[ "$ESSAI" -eq 1 ]]; then
  echo "Essai : vérifications locales faites ; rien n'est parti sur le réseau."
  exit 0
fi

# --- vérifications sur GitHub ----------------------------------------------------------------------------------------

[[ -x "$GH" ]] || fail "CLI gh introuvable"
"$GH" auth status --hostname github.com >/dev/null 2>&1 || fail "gh n'est pas connecté à github.com (gh auth login)"
origine="$(git remote get-url origin 2>/dev/null || true)"
case "$origine" in
  "https://github.com/$DEPOT_PUBLIC.git"|"git@github.com:$DEPOT_PUBLIC.git") ;;
  *) fail "origin n'est pas $DEPOT_PUBLIC (git remote add origin https://github.com/$DEPOT_PUBLIC.git)" ;;
esac
visibilite="$("$GH" api "repos/$DEPOT_PUBLIC" --jq .visibility)" || fail "GitHub injoignable (visibilité de $DEPOT_PUBLIC)"
if [[ "$visibilite" != public ]]; then
  [[ "$PRIVE" -eq 1 ]] \
    || fail "$DEPOT_PUBLIC n'est pas public ($visibilite) : rendez-le public, ou relancez avec --prive pour le peupler avant"
  echo "  ! $DEPOT_PUBLIC est $visibilite : publication acceptée par --prive ; l'amorce ne sera téléchargeable sans authentification qu'une fois le dépôt public" >&2
fi
if [[ "$IMMUABLES_VERIFIEES" -eq 0 ]]; then
  immuables="$("$GH" api "repos/$DEPOT_PUBLIC/immutable-releases" --jq .enabled 2>/dev/null || echo illisible)"
  [[ "$immuables" == true ]] \
    || fail "releases immuables non activées, ou état illisible ($immuables) : activez-les (Settings › General › Releases), ou relancez avec --immuables-verifiees après vérification à la main"
fi
if "$GH" api "repos/$DEPOT_PUBLIC/releases/tags/$tag" --jq .id >/dev/null 2>&1; then
  fail "la release $tag est déjà publiée (et immuable) : relevez AMORCE_VERSION"
fi
brouillons="$("$GH" api "repos/$DEPOT_PUBLIC/releases?per_page=100" --jq ".[] | select(.tag_name == \"$tag\") | .id")" \
  || fail "GitHub injoignable (liste des releases)"
[[ -z "$brouillons" ]] || fail "un brouillon de la release $tag existe déjà ($brouillons) : supprimez-le, puis relancez"

# sans terminal ni réponse, read reçoit une fin de fichier : set -e arrêterait le script sans rien dire
reponse=""
if ! read -r -p "Publier l'amorce $tag (version minimale $vmin) sur $DEPOT_PUBLIC ? [o/N] " reponse && [[ -z "$reponse" ]]; then
  echo >&2
  fail "confirmation impossible : aucune réponse (lancer dans un terminal, ou fournir la réponse sur l'entrée standard)"
fi
[[ "$reponse" == o || "$reponse" == oui ]] || fail "abandon demandé"

# --- publication -----------------------------------------------------------------------------------------------------

git rev-parse -q --verify "refs/tags/$tag" >/dev/null || git tag -a "$tag" -m "Amorce du Lutin Bleu $tag"
git push -q origin main
git push -q origin "$tag"

notes="Amorce d'installation du Lutin Bleu $tag.

Empreinte SHA-256 de $AMORCE :

    $empreinte

Version minimale de release du Lutin Bleu acceptée : $vmin.

Forme conseillée (télécharger, vérifier l'empreinte, lire, puis lancer) :

    curl -fsSLo $AMORCE $fixe
    shasum -a 256 $AMORCE
    bash $AMORCE

Comparez l'empreinte à celle reçue de l'auteur hors de GitHub."
"$GH" release create "$tag" "$AMORCE" --repo "$DEPOT_PUBLIC" --title "Amorce du Lutin Bleu $tag" \
  --notes "$notes" --draft --verify-tag >/dev/null
publiee="$("$GH" release view "$tag" --repo "$DEPOT_PUBLIC" --json assets \
  --jq ".assets[] | select(.name == \"$AMORCE\") | .digest // \"-\"")"
[[ "$publiee" == "sha256:$empreinte" ]] \
  || fail "empreinte publiée par GitHub ($publiee) différente de sha256:$empreinte : le brouillon $tag n'est pas publié, supprimez-le"
"$GH" release edit "$tag" --repo "$DEPOT_PUBLIC" --draft=false --latest >/dev/null
immuable="$("$GH" api "repos/$DEPOT_PUBLIC/releases/tags/$tag" --jq '.immutable // "inconnu"')"
[[ "$immuable" == true ]] || echo "  ! la release $tag ne se dit pas immuable ($immuable) : vérifiez le réglage du dépôt" >&2

mkdir -p .build
if [[ "$visibilite" == public ]]; then
  for adresse in "$fixe" "$derniere"; do
    rm -f .build/verification-amorce.sh
    /usr/bin/curl -fsSL --proto =https --proto-redir =https --tlsv1.2 -o .build/verification-amorce.sh "$adresse" \
      || fail "téléchargement anonyme de $adresse impossible"
    [[ "$(shasum -a 256 .build/verification-amorce.sh | cut -d' ' -f1)" == "$empreinte" ]] \
      || fail "l'amorce servie par $adresse n'a pas l'empreinte $empreinte"
    echo "Servie et conforme : $adresse"
  done
else
  # un dépôt privé ne sert rien sans authentification : la release se vérifie par gh, par son étiquette et comme
  # dernière release
  for quelle in "$tag" ""; do
    rm -rf .build/verification-amorce && mkdir -p .build/verification-amorce
    if [[ -n "$quelle" ]]; then
      "$GH" release download "$quelle" --repo "$DEPOT_PUBLIC" --pattern "$AMORCE" --dir .build/verification-amorce \
        || fail "téléchargement par gh de la release $quelle impossible"
    else
      "$GH" release download --repo "$DEPOT_PUBLIC" --pattern "$AMORCE" --dir .build/verification-amorce \
        || fail "téléchargement par gh de la dernière release impossible"
    fi
    [[ "$(shasum -a 256 ".build/verification-amorce/$AMORCE" | cut -d' ' -f1)" == "$empreinte" ]] \
      || fail "l'amorce servie par gh (${quelle:-dernière release}) n'a pas l'empreinte $empreinte"
    echo "Servie par gh et conforme : ${quelle:-dernière release}"
  done
  rm -rf .build/verification-amorce
fi
rm -f .build/verification-amorce.sh

cat <<EOF

Release publiée : https://github.com/$DEPOT_PUBLIC/releases/tag/$tag
EOF
if [[ "$visibilite" != public ]]; then
  cat <<EOF

Le dépôt est $visibilite : ni la commande ci-dessous ni le message aux personnes invitées ne servent avant qu'il soit public.
Le jour où il l'est, vérifier depuis un dossier vierge :
  curl -fsSLo $AMORCE $fixe && shasum -a 256 $AMORCE
L'empreinte doit être $empreinte.
EOF
fi
cat <<EOF

Message à envoyer hors de GitHub aux personnes invitées (courriel ou autre canal sûr) :
----
Pour installer le Lutin Bleu, dans Terminal :

  curl -fsSLo $AMORCE $fixe
  shasum -a 256 $AMORCE
  bash $AMORCE

L'empreinte affichée par la deuxième ligne doit être exactement :
  $empreinte
Sinon, ne lancez pas la troisième ligne et prévenez-moi.
----
Reportez aussi l'empreinte dans le README du dépôt privé (section « Installer en une commande »).
EOF
