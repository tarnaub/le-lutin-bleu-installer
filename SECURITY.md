# Signaler un problème de sécurité

Si vous pensez avoir trouvé une faille dans l'amorce (`amorce-le-lutin-bleu.sh`), ou si l'empreinte de l'amorce que
vous avez téléchargée ne correspond pas à celle publiée :

1. **Ne lancez pas l'amorce.**
2. Prévenez l'auteur directement, par un signalement privé sur ce dépôt (onglet **Security › Report a vulnerability**),
   ou par le canal par lequel il vous a transmis la clé d'installation. N'ouvrez pas de ticket public.

Indiquez la version de l'amorce, l'empreinte obtenue (`shasum -a 256 amorce-le-lutin-bleu.sh`) et l'adresse d'où vous
l'avez téléchargée.

Si la clé d'installation a pu être vue (collée dans une commande, un message, un ticket ou un fichier), prévenez
l'auteur : c'est la même clé pour tous, et lui seul peut la révoquer sur GitHub puis en transmettre une nouvelle, à
enregistrer dans le Lutin Bleu (**Compte et réglages › Mises à jour**). Elle ne s'écrit jamais nulle part ailleurs que
dans l'invite de l'amorce ou dans ce champ ; sur le Mac, elle est rangée dans le trousseau (élément `le-lutin-bleu`,
compte `depot-mises-a-jour`).
