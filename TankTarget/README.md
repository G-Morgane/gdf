# TankTarget

Petit add-on pour WoW Forever (client 1.60.1, `Interface: 16001`) : un **bouclier**
s'affiche au-dessus de la barre de nom (nameplate) du monstre que le tank cible.
Tout le groupe voit ainsi quel mob le tank tient.

- Plusieurs tanks : chaque bouclier porte le numéro du tank (1, 2…).
- **Pastille rouge** sur les monstres en combat qui tapent quelqu'un d'autre que le tank.
- Le bouclier apparaît aussi au-dessus du portrait du **cadre de cible** quand ta cible
  est celle du tank.

Les barres de nom ennemies doivent être affichées (touche `V` par défaut).

## Qui est le tank ?

Dans cet ordre :

1. le rôle de groupe « Tank » ;
2. le ou les **Main Tank** du raid (clic droit sur le joueur dans le cadre de raid) ;
3. le choix manuel avec `/tank Nom`.

Le choix manuel ne sert que si aucun rôle ni Main Tank n'est défini.

## Commandes

| Commande | Effet |
|---|---|
| `/tank` | affiche le ou les tanks détectés et les réglages |
| `/tank Nom` ou `/tank Nom1 Nom2` | choisit le ou les tanks à la main (mémorisé) |
| `/tank moi` | se déclarer tank |
| `/tank cible` | déclarer tank le joueur que tu cibles |
| `/tank effacer` | oublie le choix manuel |
| `/tank pastille` | active / désactive la pastille rouge |
| `/tank cadre` | active / désactive le bouclier sur le cadre de cible |
| `/tank taille 22` | taille du bouclier (8 à 64) |
| `/tank hauteur 4` | hauteur du bouclier au-dessus de la barre (-50 à 150) |
| `/tank debug` | ce que l'add-on voit pour ta cible (à faire en combat, utile si ça ne marche pas) |
| `/tank aide` | rappel des commandes |

`/tanktarget` marche aussi.

## Installation

Copier le dossier `TankTarget` dans
`World of Warcraft\_forever_\Interface\AddOns\`, puis relancer le jeu (ou `/reload`).

L'add-on ne touche à rien de protégé : il ajoute seulement des textures sur les
barres de nom ennemies et le cadre de cible. Il fonctionne avec les barres de nom
d'EllesmereUI (le bouclier est accroché au cadre de base de la barre de nom).
