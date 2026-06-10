# Instructions pour builder l'application (Local vs Production)

## Vue d'ensemble

L'application utilise deux paramètres dynamiques lors du build :

1. **`API_BASE_URL`** : L'URL de base de l'API backend, passée via `--dart-define` au moment du build.
2. **Nom de l'application** : Récupéré depuis la base de données (table `parametres`, clé `nom_entreprise`) via le script `scripts/update_app_name.php` qui met à jour `android/app/src/main/res/values/strings.xml`.

## Build en mode Local (Débogage / Réseau local)

### Étape 1 : Mettre à jour le nom de l'application

Le script utilise la base de données locale par défaut :

```bash
php scripts/update_app_name.php
```

### Étape 2 : Lancer le build avec l'adresse IP locale

Remplacez `192.168.1.70` par l'adresse IP de votre machine sur le réseau local :

```bash
flutter build apk --split-per-abi --dart-define=API_BASE_URL=http://192.168.1.70/Bralima_logistique/public
```

> **Note** : L'adresse IP change selon le réseau auquel vous êtes connecté. Vérifiez votre IP avec `ipconfig` (Windows) avant chaque build.

### En une seule commande

```bash
php scripts/update_app_name.php && flutter build apk --split-per-abi --dart-define=API_BASE_URL=http://192.168.1.70/Bralima_logistique/public
```

---

## Build en mode Production

### Étape 1 : Mettre à jour le nom de l'application depuis la DB production

```bash
php scripts/update_app_name.php --env=prod
```

> Si la base de données production n'est pas accessible depuis votre machine, utilisez le flag `--name` pour forcer le nom :

```bash
php scripts/update_app_name.php --name="Banyanga"
```

### Étape 2 : Lancer le build avec l'URL de production

```bash
flutter build apk --split-per-abi --dart-define=API_BASE_URL=https://suncitycesarl.com
```
# or
```bash
flutter build apk --split-per-abi --dart-define=API_BASE_URL=https://maisonbanyanga.com
```

### En une seule commande

```bash
php scripts/update_app_name.php --env=prod && flutter build apk --split-per-abi --dart-define=API_BASE_URL=https://suncitycesarl.com
```

---

## Options du script `update_app_name.php`

| Argument | Description |
|---|---|
| *(aucun)* | Utilise la base de données locale (config par défaut dans `config.php`) |
| `--env=prod` | Utilise la base de données production (lignes commentées dans `config.php`) |
| `--name="Nom Entreprise"` | Force directement le nom de l'application sans accéder à la DB |
| `--host=... --db=... --user=... --pass=...` | Paramètres de connexion DB personnalisés |

Exemples :

```bash
# Forcer un nom spécifique
php scripts/update_app_name.php --name="sun city"

# Utiliser une DB personnalisée
php scripts/update_app_name.php --host=192.168.1.100 --db=bralima_logistique --user=admin --pass=secret
```

---

## Fichiers concernés

| Fichier | Rôle |
|---|---|
| `lib/config/app_config.dart` | Lit `API_BASE_URL` via `String.fromEnvironment` |
| `android/app/src/main/res/values/strings.xml` | Contient le nom affiché sous l'icône du launcher |
| `scripts/update_app_name.php` | Script de pré-build pour mettre à jour `strings.xml` |
| `scripts/build_pre.bat` | Wrapper batch qui transmet les arguments au script PHP |
| `c:/laragon/www/Projects/Bralima_logistique/config/config.php` | Fichier de config DB (local + production) |

---

## Notes importantes

1. **`API_BASE_URL` est figé au build** : Une fois l'APK compilé, l'URL ne peut plus être changée. Il faut re-builder pour changer de serveur.

2. **Le nom sous l'icône est figé au build** : Le nom dans `strings.xml` est intégré dans l'APK. Pour le changer, il faut re-builder après avoir exécuté `update_app_name.php`.

3. **Le nom dans l'appli et l'écran "Récents" est dynamique** : `AppThemeController` met à jour le nom dans l'interface et via `SystemChrome.setApplicationSwitcherDescription` au runtime quand le paramètre `nom_entreprise` change côté backend.

4. **Vérifiez votre IP locale avant chaque build local** : L'adresse IP dépend du réseau. Utilisez `ipconfig` pour la vérifier.
