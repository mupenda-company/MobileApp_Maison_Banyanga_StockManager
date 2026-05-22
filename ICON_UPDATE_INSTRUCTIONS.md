# Instructions pour mettre à jour l'icône de l'application avec le logo de l'entreprise

## Vue d'ensemble

L'application Flutter utilise le package `flutter_launcher_icons` pour générer les icônes de l'application. Le logo de l'entreprise est affiché dans l'application via `AppThemeController.instance.companyLogo`.

## Pour mettre à jour l'icône avec le logo de l'entreprise

### Étape 1: Télécharger le logo depuis le backend

Récupérez le nom du fichier logo depuis les paramètres de l'application web (table `parametres`, clé `logo`), puis téléchargez-le:

```bash
# Remplacez l'URL et le nom du fichier logo par les vôtres
curl -o lib/assets/app_icon.png "http://your-server.com/uploads/logo.png"
```

### Étape 2: Vérifier l'image

Assurez-vous que l'image:
- Est au format PNG
- A une taille d'au moins 1024x1024 pixels pour une meilleure qualité
- A un fond transparent ou blanc de préférence

### Étape 3: Générer les icônes

Exécutez la commande suivante pour générer automatiquement toutes les tailles d'icônes nécessaires:

```bash
dart run flutter_launcher_icons
```

### Étape 4: Reconstruire l'application

Après avoir généré les icônes, reconstruisez l'application:

```bash
# Pour Android
flutter build apk --release

# Pour iOS
flutter build ios --release
```

## Affichage du logo dans l'application

Le logo de l'entreprise est déjà affiché dans l'application:
- Dans la barre de navigation (AppBar) sur la page d'accueil
- Sur l'écran de connexion (si implémenté)

Le logo est récupéré depuis les paramètres de l'application web via l'API et stocké dans `AppThemeController.instance.companyLogo`.

## Configuration actuelle

La configuration de `flutter_launcher_icons` dans `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "lib/assets/app_icon.png"
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "lib/assets/app_icon.png"
```

- `adaptive_icon_background`: Couleur de fond pour les icônes adaptatives Android (#FFFFFF = blanc)
- `adaptive_icon_foreground`: Utilise la même image pour le premier plan des icônes adaptatives

## Notes importantes

1. **L'icône du launcher est statique**: L'icône de l'application sur l'écran d'accueil du téléphone est définie au moment de la compilation, pas dynamiquement. Vous devez donc reconstruire l'application après avoir changé le logo.

2. **Logo dans l'application est dynamique**: Le logo affiché dans l'application (AppBar, etc.) est chargé dynamiquement depuis le backend et peut changer sans reconstruire l'application.

3. **Pour les mises à jour futures**: Conservez une copie du fichier `app_icon.png` original au cas où vous voudriez restaurer l'icône par défaut.