# Installer le Lutin Bleu en une commande

Ce dépôt public contient l'**amorce d'installation** du Lutin Bleu, un petit script lisible
(`amorce-le-lutin-bleu.sh`), ses tests, sa licence MIT ([LICENSE](LICENSE)), son
[SECURITY.md](SECURITY.md) (signalement privé) et son script de publication (`scripts/publier.sh`).
Le Lutin Bleu lui-même est dans un dépôt privé,
`tarnaub/le-lutin-bleu` : pour l'installer, il faut la **clé d'installation** que l'auteur transmet
lui-même, hors de GitHub. Aucun compte GitHub n'est nécessaire.

L'amorce sert sur un Mac, y compris un Mac d'entreprise sans droits administrateur. Elle ne contient aucun
code du Lutin Bleu.

## Avant de commencer

- Un Mac sous **macOS 12 ou plus récent**.
- La **clé d'installation**, reçue de l'auteur (elle commence par `github_pat_`).
- Pour faire tourner le Lutin Bleu : les **outils en ligne de commande d'Apple** (`python3`). L'installateur
  propose de les installer s'ils manquent ; sur un Mac géré, l'informatique peut devoir s'en charger.

`gh`, l'outil en ligne de commande de GitHub, n'est pas nécessaire. S'il est installé, l'amorce ne le lance
pas et le dit en une ligne.

Aucun droit administrateur n'est demandé. Ne lancez jamais l'amorce avec `sudo` : elle refuse.

## La commande

### Forme conseillée : télécharger, vérifier, puis lancer

Dans Terminal :

```sh
curl -fsSLo amorce-le-lutin-bleu.sh https://github.com/tarnaub/le-lutin-bleu-installer/releases/download/v1.1.0/amorce-le-lutin-bleu.sh
shasum -a 256 amorce-le-lutin-bleu.sh
bash amorce-le-lutin-bleu.sh
```

1. La première ligne télécharge l'amorce de la version v1.1.0, à une adresse qui ne change pas.
2. La deuxième affiche son empreinte SHA-256. Elle doit être **exactement** celle du tableau ci-dessous, et
   celle que l'auteur vous a envoyée hors de GitHub. Si elle diffère, ne lancez pas la troisième ligne et
   prévenez l'auteur.
3. La troisième lance l'amorce, qui demande la clé d'installation. Vous pouvez d'abord la lire :
   `less amorce-le-lutin-bleu.sh`.

Pour toujours prendre la dernière version de l'amorce, remplacez `download/v1.1.0` par `latest/download`
dans la première ligne. Vérifiez alors l'empreinte avec celle de la dernière version du tableau.

### Forme courte

```sh
curl -fsSL https://github.com/tarnaub/le-lutin-bleu-installer/releases/latest/download/amorce-le-lutin-bleu.sh | bash
```

Elle exécute l'amorce au fil du téléchargement, sans que vous puissiez la lire ni vérifier son empreinte.
Elle convient si vous faites confiance à cette adresse. Sur un Mac d'entreprise, préférez la forme
conseillée : un logiciel de sécurité peut signaler un script téléchargé et exécuté directement, ce qui est
son rôle.

Si le téléchargement se coupe en route, l'amorce n'exécute rien : tout le script est fait de fonctions, et
la seule commande est sa dernière ligne.

### Options

Les options se placent après `bash amorce-le-lutin-bleu.sh` (ou après `bash -s --` dans la forme courte) :

| Option | Effet |
|---|---|
| `--dossier DOSSIER` | où installer (par défaut : `~/Documents/LeLutinBleu`) |
| `--sans-lancement` | ne lance pas le Lutin Bleu à la fin |
| `--sans-restauration` | ne propose pas de restaurer d'anciennes conversations |
| `--restaurer` | restaure toutes les anciennes conversations |
| `--aide` | l'aide |

La clé ne se donne jamais dans la commande : l'amorce refuse un argument qui ressemble à une clé, parce
qu'elle resterait dans l'historique du Terminal.

## Empreintes

| Version | Empreinte SHA-256 de `amorce-le-lutin-bleu.sh` |
|---|---|
| v1.1.0 | `d0358b94d8a95cb3cfd4096641004dbb4e071ac3673b1b4935c51b36bc0beae8` |
| v1.0.0 | `de2d4f074b5080c469885e1be8e65daaf10e11874c8d1c4937ceda7563007ad4` (par `gh` ou un jeton classique, remplacée par la v1.1.0) |

L'auteur envoie aussi l'empreinte par un autre canal que GitHub (courriel aux personnes à qui il donne la
clé). Le README
du dépôt privé la reprend. Les releases de ce dépôt sont immuables : le fichier d'une version publiée ne
peut plus être remplacé.

## D'où vient cette amorce

Ce dépôt est la publication de l'amorce. Sa source est tenue dans le dépôt privé du Lutin Bleu, à côté de
l'installateur dont elle dépend : chaque version du Lutin Bleu rejoue ses tests, et une amorce modifiée doit y
avoir sa version relevée, sa nouvelle empreinte dans les deux README et la même clé de signature que le Lutin
Bleu. Elle est ensuite copiée ici, commitée, puis publiée par `scripts/publier.sh` dans une nouvelle release
immuable, juste après la release du Lutin Bleu qui l'accompagne ; son empreinte est alors envoyée hors de
GitHub.

## Ce que fait l'amorce

1. **Les prérequis** : un Mac, macOS 12 ou plus, pas `sudo`, les outils fournis avec macOS (`curl`,
   `ssh-keygen`, `shasum`, `plutil`). Elle signale l'absence des outils d'Apple sans lancer `python3`.
2. **La clé d'installation** : elle dit sa portée (ci-dessous), la demande sans écho, puis la vérifie sur
   les deux dépôts, `tarnaub/le-lutin-bleu` et `tarnaub/le-lutin-bleu-installer`, avant tout
   téléchargement. Une clé refusée (révoquée, expirée ou mal copiée), une clé qui n'ouvre qu'un des deux
   dépôts, ou un jeton classique (`ghp_…`) sont refusés avec leur motif ; après trois refus, elle s'arrête.
3. **Le téléchargement** de l'installateur de la dernière release du Lutin Bleu, avec son manifeste et la
   signature de ce manifeste, uniquement depuis l'API GitHub du dépôt `tarnaub/le-lutin-bleu`.
4. **Les vérifications**, avant d'exécuter quoi que ce soit :
   - la signature du manifeste, avec la clé publique écrite dans l'amorce ;
   - le format du manifeste, la version et le dépôt qu'il nomme ;
   - l'empreinte de l'installateur téléchargé, contre celle du manifeste signé, puis contre celle que publie
     GitHub ;
   - la version : une release plus ancienne que la version minimale connue de l'amorce est refusée, même
     signée (protection contre le retour à une ancienne version).

   Si la dernière release vient d'être publiée et n'est pas encore signée, l'amorce le dit et n'installe
   rien : réessayez quelques minutes plus tard.
5. **Le lancement de l'installateur** du Lutin Bleu, qui reçoit la clé par un tuyau, télécharge
   l'application de la même version et la vérifie contre le même manifeste signé. Il installe dans votre
   dossier personnel, règle les autorisations de macOS, range la clé dans le trousseau du Mac pour les mises
   à jour et propose de lancer le Lutin Bleu. Pour lire la release, il n'emploie que la clé, jamais `gh`.

Clé publique de signature des releases, écrite dans l'amorce :

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILuYLtEHQV+fa6MNxO5hnKH9ABioy0LelC9ku0S9UeJR
```

## La clé d'installation et sa portée

L'amorce affiche l'essentiel avant de la demander.

- C'est un **jeton GitHub à grain fin** créé par l'auteur : il ouvre **en lecture seule** les deux dépôts
  des versions, `tarnaub/le-lutin-bleu` et `tarnaub/le-lutin-bleu-installer`, **et rien d'autre**. Il ne
  permet ni d'écrire, ni de lire un autre dépôt, ni d'agir sur votre compte GitHub : vous n'en avez pas
  besoin.
- C'est **la même clé pour toutes les personnes** qui installent le Lutin Bleu, sans expiration. Elle permet
  de lire le code du Lutin Bleu, pas d'en faire installer un autre : l'amorce, puis l'installateur, refusent
  tout ce que la clé de signature de l'auteur n'a pas signé.
- **Elle ne s'affiche pas** pendant la frappe, passe à `curl` par un tuyau (jamais sur une ligne de commande
  visible par les autres programmes, jamais sur le disque) et à l'installateur de la même manière. Une clé
  collée reste toutefois dans le presse-papiers jusqu'à la copie suivante.
- **L'amorce ne l'écrit nulle part.** C'est l'installateur, une fois sa signature vérifiée, qui la range
  dans le **trousseau du Mac** (élément `le-lutin-bleu`, compte `depot-mises-a-jour`), à la fin d'une
  installation réussie : le Lutin Bleu s'en sert pour ses mises à jour.
- Ne la collez jamais dans une commande, un message, un ticket ou un fichier. Si elle a pu être vue,
  prévenez l'auteur : il la révoque et vous en donne une nouvelle.

Pour la remplacer ou la retirer ensuite : dans le Lutin Bleu, **Compte et réglages › Mises à jour**
(« Retirer la clé »), ou dans l'app **Trousseau d'accès**, l'élément `le-lutin-bleu` du compte
`depot-mises-a-jour`.

## Mettre à jour

- La page du Lutin Bleu propose elle-même les mises à jour, par la clé rangée dans le trousseau.
- Vous pouvez aussi relancer la même commande : l'amorce installe la dernière release, et l'ancienne version
  part à la Corbeille. Vos conversations et réglages sont gardés.

## Réseau d'entreprise

L'amorce contacte seulement `api.github.com` et le stockage des fichiers de release de GitHub
(`*.githubusercontent.com`, aujourd'hui `release-assets.githubusercontent.com`). L'installateur du Lutin Bleu peut ensuite proposer d'installer Cursor Agent depuis
`cursor.com`.

Derrière un proxy, déclarez-le avant de lancer l'amorce (`curl` ne lit pas les réglages de proxy de macOS) :

```sh
export https_proxy=http://proxy.exemple:8080
```

Un proxy qui inspecte le trafic chiffré peut faire échouer `curl` ; l'amorce le signale, et c'est à voir
avec votre informatique.

## Tests

Les tests jouent l'amorce contre un faux GitHub local (127.0.0.1), avec des clés de signature d'essai
créées à chaque passage, des clés d'installation factices, un faux `gh` qui ne doit jamais être lancé, un
faux proxy et un installateur factice qui n'installe rien. Ils jouent aussi
`scripts/publier.sh` sur une copie de ce dépôt, avec un autre faux `gh`, jusqu'à sa confirmation (sans réponse, puis
avec « n ») : rien n'est poussé ni publié. Ils ne contactent jamais GitHub.

```sh
bash tests/lancer-tests.sh
```

Il faut `shellcheck` (`brew install shellcheck`) et le `python3` des outils d'Apple. Les résultats sont dans
`tests/.essais/resultats.md`.

## Licence

Ce dépôt est publié sous licence MIT : voir [LICENSE](LICENSE). Le Lutin Bleu lui-même reste dans son
dépôt privé.

## Signaler un problème

Voir [SECURITY.md](SECURITY.md).
