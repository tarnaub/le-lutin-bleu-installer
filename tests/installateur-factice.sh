#!/bin/bash
# Installateur factice des tests de l'amorce : n'installe rien. Il écrit dans un témoin ses arguments, s'il a reçu un
# jeton par le descripteur nommé dans LUTIN_BLEU_JETON_FD (sans jamais écrire le jeton) et si un autre descripteur de
# l'amorce lui a échappé.
jeton_recu="non"
if [ "${LUTIN_BLEU_JETON_FD:-}" = 3 ]; then
  t=""
  IFS= read -r t <&3 || true
  [ -n "$t" ] && jeton_recu="oui (${#t} caractères)"
  t=""
fi
fuite="non"
if [ -e /dev/fd/4 ]; then
  fuite="oui ($(/usr/sbin/lsof -a -p $$ -d 4 -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1))"
fi
{
  echo "installateur factice lancé"
  echo "arguments : $*"
  echo "jeton reçu par le descripteur 3 : $jeton_recu"
  echo "descripteur 4 ouvert : $fuite"
} > "${LUTIN_TEST_TEMOIN:?témoin non défini}"
echo "Installateur factice : témoin écrit."
