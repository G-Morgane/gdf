# GuildScribe – registre de guilde pour WoW Forever

```
WoW + add-on GuildScribe ──(déconnexion / reload)──► GuildScribe.lua sur le PC
                                                          │
                              GuildScribe.exe (icône près de l'horloge, lancée avec le jeu)
                                                          │ envoi auto dès que le fichier change
                                                          ▼
                                        Supabase (base + connexion Discord)
                                                          ▲
                                   site web sur Vercel ───┘  réservé au serveur Discord
```

| Dossier | Rôle |
|---|---|
| `GuildScribe/` | l'add-on WoW (Interface 16001) |
| `uploader/` | `GuildScribe.cs` : installe l'add-on et envoie son fichier à Supabase |
| `kit/` | fabrication du zip à partager (`Build-MemberKit.ps1`) |
| `supabase/schema.sql` | tables, sécurité, fonction d'ingestion |
| `web/` | le site (HTML/JS sans build) + `api/claim.js` (vérification Discord) |

Un add-on ne peut pas accéder à Internet : c'est pour ça qu'il y a l'uploader. **Un seul officier équipé suffit** pour tout le roster. Les fiches détaillées (métiers, équipement, iLvl) viennent des membres qui ont installé l'add-on.

---

## 1. L'add-on

Copier `GuildScribe/` dans `World of Warcraft\_forever_\Interface\AddOns\`. Il travaille tout seul (scan à la connexion, envoi de sa fiche aux autres à chaque changement de niveau, de métier ou d'équipement). Commandes facultatives : `/gs stats`, `/gs sync`, `/gs export`.

## 2. Supabase

1. Crée un projet sur supabase.com.
2. **SQL Editor** > colle tout `supabase/schema.sql` > **Run**.
3. Crée un jeton d'upload par personne qui fera tourner l'uploader :
   ```sql
   select public.create_upload_token('Morgane');
   ```
   Copie le résultat, il ne sera plus affiché. Pour couper un jeton : `update upload_tokens set revoked = true where label = 'Morgane';`
4. Note dans **Project Settings > API** : l'URL du projet, la clé **anon/publishable** et la clé **service_role/secret**.

## 3. Discord

1. Sur discord.com/developers/applications : **New Application**. Dans **OAuth2**, ajoute le redirect `https://<ton-projet>.supabase.co/auth/v1/callback`. Copie le Client ID et le Client Secret.
2. Supabase > **Authentication > Sign In / Providers > Discord** : active-le, colle l'ID et le secret.
3. Dans Discord (mode développeur activé dans Paramètres > Avancés) : clic droit sur le serveur de la guilde > **Copier l'identifiant**, et pareil sur chaque rôle d'officier (Paramètres du serveur > Rôles).

Règle d'accès : quelqu'un qui est sur le serveur Discord = **membre** ; quelqu'un qui a un rôle officier = **officier** (voit les notes d'officier). L'accès est revérifié à chaque connexion et expire après 30 jours sans reconnexion. Quitter le Discord retire l'accès à la connexion suivante.

## 4. Vercel

1. Mets ce dossier sur un dépôt GitHub, puis sur vercel.com : **Add New > Project**, importe le dépôt.
2. Framework : *Other*, pas de commande de build. **Root Directory** : vide ou `web`, les deux marchent (`vercel.json` et `api/claim.js` à la racine gèrent le cas vide).
3. **Environment Variables** :
   | Nom | Valeur |
   |---|---|
   | `SUPABASE_URL` | `https://<ton-projet>.supabase.co` |
   | `SUPABASE_SERVICE_ROLE_KEY` | clé service_role / secret (jamais dans le code du site !) |
   | `DISCORD_GUILD_ID` | ID du serveur Discord |
   | `DISCORD_OFFICER_ROLE_IDS` | IDs des rôles officiers, séparés par des virgules |
4. Remplis `web/config.js` avec l'URL Supabase et la clé **anon/publishable** (elles sont faites pour être publiques), puis redéploie.
5. Supabase > **Authentication > URL Configuration** : *Site URL* = l'adresse Vercel (ex. `https://ma-guilde.vercel.app`), et ajoute-la aussi dans *Redirect URLs*.

Sans `config.js` rempli (ou avec `?demo` dans l'URL), le site s'ouvre en **mode démo** avec des données fictives.
Prévisualisation locale : `powershell -File web/dev-server.ps1` puis http://localhost:8080.

## 5. GuildScribe.exe : installation et envoi (officiers et membres)

Un seul programme, `GuildScribe.exe` (source : `uploader/GuildScribe.cs`, compilé avec le compilateur C# fourni avec Windows, rien à installer). Pas de PowerShell caché ni de démarrage avec Windows : les antivirus (Norton, Avast/AVG…) bloquaient ce fonctionnement.

1. Dans Supabase, crée un jeton commun : `select public.create_upload_token('Membres');`
2. Fabrique le zip (compile l'exe et y met l'add-on, le jeton et l'adresse du site) :
   ```powershell
   powershell -ExecutionPolicy Bypass -File kit\Build-MemberKit.ps1 -UploadToken <jeton Membres>
   ```
3. Partage `GuildScribe-Installateur.zip`. On décompresse, on double-clique sur `GuildScribe.exe` (voir `kit/LISEZMOI.txt`) :
   - il trouve WoW Forever (ou demande le dossier), copie l'add-on, s'installe dans `%LOCALAPPDATA%\GuildScribe\app` ;
   - il crée le raccourci **« WoW Forever + GuildScribe »** sur le bureau (et « GuildScribe » dans le menu Démarrer, sans lancer le jeu).
4. Ce raccourci lance le jeu et affiche une icône près de l'horloge. Elle envoie le fichier de l'add-on à chaque `/reload` ou déconnexion, puis se ferme 40 s après la fermeture du jeu. Clic droit : envoyer maintenant, ouvrir le site, journal.

- **Officiers** : un jeton personnel déjà présent dans `%APPDATA%\GuildScribe\config.json` est conservé quand on installe le kit membres.
- Relancer `GuildScribe.exe` du kit : Oui = mettre à jour, Non = désinstaller.
- Journal : `%APPDATA%\GuildScribe\uploader.log`. Tests : `GuildScribe.exe --once` (un envoi), `GuildScribe.exe --dump GuildScribe.lua sortie.json` (conversion locale sans envoi).
- Vérifier le contenu du fichier sans rien envoyer : `uploader\Export-GuildScribe.ps1 -Out guild.json`.

Le jeton commun est lisible dans le zip : s'il fuit, `update upload_tokens set revoked = true where label = 'Membres';`, crée-en un autre et refais le zip.

Les données arrivent sur le site à chaque **déconnexion** ou `/reload` (c'est le seul moment où WoW écrit le fichier).
---

## Données collectées

| Source | Qui | Données |
|---|---|---|
| Roster | **tous** les membres | nom, rang, niveau, classe, zone, note publique, note d'officier (si l'uploader a le droit de la voir), en ligne, dernière connexion, hauts faits, départs |
| Annuaire des métiers de guilde | tous, **si le client Forever a cette API** | métier + niveau |
| Banque de guilde | quand un membre équipé l'ouvre, **si Forever en a une** | objets par onglet, or de la guilde |
| Fiche add-on, partagée en jeu | membres **avec GuildScribe** | race, faction, titre, XP, iLvl, spécialisation, équipement complet (objet, niveau, enchantement, gemmes, suffixe, durabilité), talents point par point, métiers, **recettes** (avec temps de recharge), statistiques, résistances, raids verrouillés, JcJ, compétences d'armes, réputations |
| Fiche add-on, envoyée seulement par l'uploader du joueur | membres **avec le kit** | contenu des sacs et de la banque, quêtes terminées et en cours, montures, monnaies |

Les recettes sont lues quand le joueur ouvre la fenêtre de son métier, la banque quand il l'ouvre. L'or du joueur et les infos de compte ne sont jamais envoyés.

**Fusion** : chaque section a sa date. Le site garde la plus récente, quelle que soit la personne qui l'a envoyée, et ne perd jamais une section absente d'un envoi.

**Pas besoin de redistribuer l'add-on pour afficher plus de choses** : tout ce qui est collecté arrive déjà dans Supabase, le site peut être enrichi sans toucher à l'add-on. Et une version plus récente de l'add-on peut ajouter des sections : les anciennes versions les relaient quand même. Quand un membre voit quelqu'un avec une version plus récente, l'add-on lui conseille de reprendre le zip.

Partage en jeu : les **officiers** (ou `/gs collecteur`) demandent les fiches qui leur manquent aux membres connectés ; les autres n'envoient que ce qui a changé.

## À vérifier au premier lancement

- WoW Forever (patch 1.60.1) est récent. Il faut confirmer en jeu que l'annuaire des métiers de guilde, `GetProfessions` et `GetSpecialization` existent. Chaque appel est protégé : s'ils manquent, ces infos ne viennent que des membres qui ont l'add-on.
- Les liens d'objets pointent vers Wowhead Classic (`itemUrl` dans `web/config.js`), à adapter si Wowhead ouvre une section Forever.
