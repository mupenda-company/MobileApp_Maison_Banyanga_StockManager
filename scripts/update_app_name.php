#!/usr/bin/env php
<?php
/**
 * Pré-build : met à jour le nom de l'application dans strings.xml
 * à partir des paramètres de personnalisation de la base de données.
 * 
 * Usage:
 *   php update_app_name.php                    # utilise la DB locale (défaut)
 *   php update_app_name.php --env=prod         # utilise la DB production
 *   php update_app_name.php --host=... --db=... --user=... --pass=...  # DB custom
 *   php update_app_name.php --name="Mon Entreprise"  # forcer un nom directement
 *
 * Ce script est appelé automatiquement avant flutter build apk
 * via le hook scripts/build_pre.bat
 */

// --- Parser les arguments CLI ---
$args = [];
for ($i = 1; $i < $argc; $i++) {
    if (preg_match('/^--(\w+)=(.+)$/', $argv[$i], $m)) {
        $args[$m[1]] = $m[2];
    } elseif (preg_match('/^--(\w+)$/', $argv[$i], $m)) {
        $args[$m[1]] = true;
    }
}

// --- Mode : nom forcé directement ---
if (!empty($args['name'])) {
    $companyName = trim($args['name']);
    echo "update_app_name: nom forcé via --name → \"$companyName\"\n";
    updateStringsXml($companyName);
    exit(0);
}

// --- Déterminer la config DB ---
$dbHost = $args['host'] ?? null;
$dbName = $args['db'] ?? null;
$dbUser = $args['user'] ?? null;
$dbPass = $args['pass'] ?? null;

// Si --env=prod, utiliser la config production du fichier
if (!empty($args['env']) && $args['env'] === 'prod') {
    $configFile = 'c:/laragon/www/Projects/Bralima_logistique/config/config.php';
    if (!file_exists($configFile)) {
        echo "update_app_name: config non trouvé pour prod\n";
        exit(0);
    }
    $configContent = file_get_contents($configFile);
    // Parser les lignes commentées (production)
    preg_match_all("/\/\/\s*define\('DB_(HOST|NAME|USER|PASS)',\s*'([^']*)'\)/", $configContent, $matches, PREG_SET_ORDER);
    $prodConfig = [];
    foreach ($matches as $m) {
        $prodConfig[$m[1]] = $m[2];
    }
    if (!empty($prodConfig)) {
        $dbHost = $dbHost ?? $prodConfig['HOST'] ?? null;
        $dbName = $dbName ?? $prodConfig['NAME'] ?? null;
        $dbUser = $dbUser ?? $prodConfig['USER'] ?? null;
        $dbPass = $dbPass ?? $prodConfig['PASS'] ?? null;
        echo "update_app_name: utilisation de la config PRODUCTION\n";
    } else {
        echo "update_app_name: config production non trouvée dans le fichier, fallback local\n";
    }
}

// Si pas encore de config, lire la config locale
if ($dbHost === null) {
    $configFile = 'c:/laragon/www/Projects/Bralima_logistique/config/config.php';
    if (!file_exists($configFile)) {
        echo "update_app_name: config non trouvé ($configFile), nom par défaut conservé\n";
        exit(0);
    }
    $configContent = file_get_contents($configFile);
    preg_match("/define\('DB_HOST',\s*'([^']+)'\)/", $configContent, $hostMatch);
    preg_match("/define\('DB_NAME',\s*'([^']+)'\)/", $configContent, $nameMatch);
    preg_match("/define\('DB_USER',\s*'([^']+)'\)/", $configContent, $userMatch);
    preg_match("/define\('DB_PASS',\s*'([^']*)'\)/", $configContent, $passMatch);
    $dbHost = $hostMatch[1] ?? 'localhost';
    $dbName = $nameMatch[1] ?? 'bralima_logistique';
    $dbUser = $userMatch[1] ?? 'root';
    $dbPass = $passMatch[1] ?? '';
    echo "update_app_name: utilisation de la config LOCALE\n";
}

try {
    $pdo = new PDO("mysql:host=$dbHost;dbname=$dbName", $dbUser, $dbPass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $row = $pdo->query("SELECT valeur FROM parametres WHERE cle = 'nom_entreprise' LIMIT 1")->fetch(PDO::FETCH_ASSOC);
    
    if (!$row || empty($row['valeur'])) {
        echo "update_app_name: nom_entreprise non trouvé dans la DB\n";
        exit(0);
    }
    
    $companyName = trim($row['valeur']);
    updateStringsXml($companyName);
    
} catch (PDOException $e) {
    echo "update_app_name: erreur DB → " . $e->getMessage() . "\n";
    exit(0); // Ne pas bloquer le build
}

function updateStringsXml(string $companyName): void {
    $stringsPath = dirname(__DIR__) . '/android/app/src/main/res/values/strings.xml';
    if (!file_exists($stringsPath)) {
        echo "update_app_name: strings.xml non trouvé\n";
        exit(1);
    }
    
    $content = file_get_contents($stringsPath);
    $newContent = preg_replace(
        '/<string name="app_name">[^<]*<\/string>/',
        '<string name="app_name">' . htmlspecialchars($companyName, ENT_XML1) . '</string>',
        $content
    );
    
    if ($newContent !== $content) {
        file_put_contents($stringsPath, $newContent);
        echo "update_app_name: nom mis à jour → \"$companyName\"\n";
    } else {
        echo "update_app_name: nom inchangé → \"$companyName\"\n";
    }
}
