# Installer le Lutin Bleu en une commande

Ce dépôt public contient l'**amorce d'installation** du Lutin Bleu, un petit script lisible
(`amorce-le-lutin-bleu.sh`), ses tests, sa licence MIT ([LICENSE](LICENSE)), son
[SECURITY.md](SECURITY.md) (signalement privé) et son script de publication (`scripts/publier.sh`).
Le Lutin Bleu lui-même est dans un dépôt privé,
`tarnaub/le-lutin-bleu` : seules les personnes que l'auteur y a invitées peuvent l'installer, chacune avec
son propre compte GitHub.

L'amorce sert sur un Mac, y compris un Mac d'entreprise sans droits administrateur. Elle ne contient aucun
code du Lutin Bleu.

## Avant de commencer

- Un Mac sous **macOS 12 ou plus récent**.
- Un **compte GitHub invité** sur `tarnaub/le-lutin-bleu`, invitation acceptée (lien reçu par courriel ou
  dans les notifications de GitHub).
- Pour faire tourner le Lutin Bleu : les **outils en ligne de commande d'Apple** (`python3`). L'installateur
  propose de les installer s'ils manquent ; sur un Mac géré, l'informatique peut devoir s'en charger.
- Facultatif : `gh`, l'outil en ligne de commande de GitHub. Avec lui, la connexion se fait dans le
  navigateur et la mise à jour depuis la page du Lutin Bleu fonctionne. Sans lui, l'amorce demande un jeton.

Aucun droit administrateur n'est demandé. Ne lancez jamais l'amorce avec `sudo` : elle refuse.

## La commande

### Forme conseillée : télécharger, vérifier, puis lancer

Dans Terminal :

```sh
curl -fsSLo amorce-le-lutin-bleu.sh https://github.com/tarnaub/le-lutin-bleu-installer/releases/download/v1.0.0/amorce-le-lutin-bleu.sh
shasum -a 256 amorce-le-lutin-bleu.sh
bash amorce-le-lutin-bleu.sh
```

1. La première ligne télécharge l'amorce de la version v1.0.0, à une adresse qui ne change pas.
2. La deuxième affiche son empreinte SHA-256. Elle doit être **exactement** celle du tableau ci-dessous, et
   celle que l'auteur vous a envoyée hors de GitHub. Si elle diffère, ne lancez pas la troisième ligne et
   prévenez l'auteur.
3. La troisième lance l'amorce. Vous pouvez d'abord la lire : `less amorce-le-lutin-bleu.sh`.

Pour toujours prendre la dernière version de l'amorce, remplacez `download/v1.0.0` par `latest/download`
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

Aucun jeton ne se donne dans la commande : l'amorce refuse un argument qui ressemble à un jeton, parce
qu'il resterait dans l'historique du Terminal.

## Empreintes

| Version | Empreinte SHA-256 de `amorce-le-lutin-bleu.sh` |
|---|---|
| v1.0.0 | `de2d4f074b5080c469885e1be8e65daaf10e11874c8d1c4937ceda7563007ad4` |

L'auteur envoie aussi l'empreinte par un autre canal que GitHub (courriel aux personnes invitées). Le README
du dépôt privé la reprend. Les releases de ce dépôt sont immuables : le fichier d'une version publiée ne
peut plus être remplacé.

## Ce que fait l'amorce

1. **Les prérequis** : un Mac, macOS 12 ou plus, pas `sudo`, les outils fournis avec macOS (`curl`,
   `ssh-keygen`, `shasum`, `plutil`). Elle signale l'absence des outils d'Apple sans lancer `python3`.
2. **L'accès au dépôt privé**, dans cet ordre :
   - `gh` déjà connecté : elle s'en sert, sans rien changer à cette connexion ;
   - sinon, elle explique la portée de l'accès (ci-dessous), puis propose la connexion `gh` dans le
     navigateur si `gh` est installé ;
   - sinon, elle demande un jeton, saisi sans écho.
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
5. **Le lancement de l'installateur** du Lutin Bleu, qui télécharge l'application de la même version et la
   vérifie contre le même manifeste signé. Il installe dans votre dossier personnel, règle les
   autorisations de macOS et propose de lancer le Lutin Bleu.

Clé publique de signature des releases, écrite dans l'amorce :

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILuYLtEHQV+fa6MNxO5hnKH9ABioy0LelC9ku0S9UeJR
```

## L'accès demandé et sa portée

À lire avant de vous connecter. L'amorce affiche le même avertissement.

- Le dépôt `tarnaub/le-lutin-bleu` appartient à un **compte GitHub personnel**. Sur un tel dépôt, GitHub ne
  permet **ni un accès en lecture seule, ni un jeton « à grain fin » limité à ce seul dépôt** : une personne
  invitée ne peut pas choisir ce dépôt dans le formulaire d'un jeton à grain fin.
- La **connexion `gh`** (portées `repo`, `read:org` et `gist`) comme un **jeton classique `repo`** ouvrent,
  en lecture **et en écriture**, **tous les dépôts auxquels votre compte GitHub a accès**, y compris ceux de
  votre employeur si votre compte est membre de son organisation GitHub (sauf si cette organisation
  restreint les jetons classiques).
- **Si vous choisissez le jeton** : créez un jeton classique sur
  [github.com/settings/tokens/new](https://github.com/settings/tokens/new?scopes=repo&description=Installation+du+Lutin+Bleu),
  cochez la seule case `repo`, choisissez **la durée la plus courte (7 jours)**, et supprimez-le après
  l'installation. Ne collez jamais un jeton dans la commande, un message ou un fichier.
- **L'amorce ne garde rien** : le jeton ne s'affiche pas pendant la frappe, passe à `curl` par un tuyau
  (jamais sur une ligne de commande visible par les autres programmes, jamais sur le disque), est transmis à
  l'installateur de la même manière, puis oublié. Rien n'est rangé dans le trousseau. Un jeton collé reste
  toutefois dans le presse-papiers jusqu'à la copie suivante.
- **La connexion `gh`**, elle, reste dans le trousseau du Mac, comme pour tout usage de `gh`, jusqu'à
  `gh auth logout`.
- Utilisez **votre propre compte**, jamais le jeton de quelqu'un d'autre.

Pour retirer l'accès ensuite :

- jeton : supprimez-le sur [github.com/settings/tokens](https://github.com/settings/tokens) ;
- connexion `gh` : `gh auth logout`, et retirez l'application **GitHub CLI** dans
  **Settings › Applications › Authorized OAuth Apps**.

## Mettre à jour

- Avec `gh` connecté, la page du Lutin Bleu propose elle-même les mises à jour.
- Sans `gh`, relancez la même commande : l'amorce installe la dernière release, et l'ancienne version part
  à la Corbeille. Vos conversations et réglages sont gardés.

## Réseau d'entreprise

L'amorce contacte seulement `api.github.com` et le stockage des fichiers de release de GitHub
(`*.githubusercontent.com`, aujourd'hui `release-assets.githubusercontent.com`) ; la connexion `gh` passe
aussi par `github.com`. L'installateur du Lutin Bleu peut ensuite proposer d'installer Cursor Agent depuis
`cursor.com`.

Derrière un proxy, déclarez-le avant de lancer l'amorce (`curl` ne lit pas les réglages de proxy de macOS) :

```sh
export https_proxy=http://proxy.exemple:8080
```

Un proxy qui inspecte le trafic chiffré peut faire échouer `curl` ; l'amorce le signale, et c'est à voir
avec votre informatique.

## Tests

Les tests jouent l'amorce contre un faux GitHub local (127.0.0.1), avec des clés d'essai créées à chaque
passage, un faux `gh`, un faux proxy et un installateur factice qui n'installe rien. Ils ne contactent jamais
GitHub.

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
