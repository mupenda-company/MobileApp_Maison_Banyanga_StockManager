<?php
$root = $argv[1] ?? '';
if (!$root || !is_dir($root)) {
    fwrite(STDERR, "Invalid root\n");
    exit(1);
}

function writeFileUtf8(string $path, string $content): void
{
    file_put_contents($path, $content);
}

function replaceOnce(string $path, string $search, string $replace): void
{
    $content = str_replace("\r\n", "\n", file_get_contents($path));
    $updated = str_replace($search, $replace, $content, $count);
    if ($count !== 1) {
        fwrite(STDERR, "Replacement count {$count} in {$path}\nAnchor: " . substr($search, 0, 120) . "\n");
        exit(2);
    }
    file_put_contents($path, $updated);
}

@mkdir($root . '/app/Views/manquants', 0777, true);

writeFileUtf8($root . '/app/Models/Manquant.php', <<<'PHP'
<?php

class Manquant extends Model
{
    protected $table = 'manquants_agents';
    protected $fillable = [
        'agent_id', 'produit_id', 'quantite_caisses', 'montant', 'montant_paye',
        'date_manquant', 'date_reglement', 'motif', 'notes_reglement', 'statut', 'created_by'
    ];

    public function getWithDetails($filters = [])
    {
        $where = '1=1';
        $params = [];
        foreach (['agent_id', 'produit_id'] as $field) {
            if (!empty($filters[$field])) {
                $where .= " AND m.{$field} = :{$field}";
                $params[$field] = $filters[$field];
            }
        }
        if (!empty($filters['statut'])) {
            if ($filters['statut'] === 'paye') {
                $where .= " AND m.statut IN ('paye', 'regle')";
            } else {
                $where .= " AND m.statut = :statut";
                $params['statut'] = $filters['statut'];
            }
        }
        if (!empty($filters['date_debut'])) {
            $where .= ' AND m.date_manquant >= :date_debut';
            $params['date_debut'] = $filters['date_debut'];
        }
        if (!empty($filters['date_fin'])) {
            $where .= ' AND m.date_manquant <= :date_fin';
            $params['date_fin'] = $filters['date_fin'];
        }

        return $this->db->fetchAll(
            "SELECT m.*, CONCAT(a.prenom, ' ', a.nom) AS agent_nom, p.nom AS produit_nom,
                    p.code AS produit_code, CONCAT(u.prenom, ' ', u.nom) AS createur_nom,
                    GREATEST(COALESCE(m.montant, 0) - COALESCE(m.montant_paye, 0), 0) AS reste_montant
             FROM manquants_agents m
             JOIN users a ON a.id = m.agent_id
             LEFT JOIN produits p ON p.id = m.produit_id
             LEFT JOIN users u ON u.id = m.created_by
             WHERE {$where}
             ORDER BY m.date_manquant DESC, a.nom, a.prenom",
            $params
        );
    }

    public function getSummaryByAgent($filters = [])
    {
        $where = '1=1';
        $params = [];
        if (!empty($filters['agent_id'])) { $where .= ' AND m.agent_id = :agent_id'; $params['agent_id'] = $filters['agent_id']; }
        if (!empty($filters['date_debut'])) { $where .= ' AND m.date_manquant >= :date_debut'; $params['date_debut'] = $filters['date_debut']; }
        if (!empty($filters['date_fin'])) { $where .= ' AND m.date_manquant <= :date_fin'; $params['date_fin'] = $filters['date_fin']; }

        return $this->db->fetchAll(
            "SELECT m.agent_id, CONCAT(a.prenom, ' ', a.nom) AS agent_nom, COUNT(*) AS nombre,
                    COALESCE(SUM(m.quantite_caisses), 0) AS total_caisses,
                    COALESCE(SUM(m.montant), 0) AS total_montant,
                    COALESCE(SUM(m.montant_paye), 0) AS total_paye,
                    COALESCE(SUM(GREATEST(m.montant - m.montant_paye, 0)), 0) AS total_reste
             FROM manquants_agents m
             JOIN users a ON a.id = m.agent_id
             WHERE {$where}
             GROUP BY m.agent_id, a.prenom, a.nom
             ORDER BY total_reste DESC, total_montant DESC",
            $params
        );
    }

    public function enregistrerPaiement($id, $montant, $datePaiement, $note, $createdBy)
    {
        $montant = round(max(0, (float) $montant), 2);
        if ($montant <= 0) {
            return ['success' => false, 'message' => 'Le montant payé doit être supérieur à 0.'];
        }

        try {
            $this->db->beginTransaction();
            $manquant = $this->find($id);
            if (!$manquant) {
                throw new Exception('Manquant introuvable.');
            }

            $total = (float) ($manquant['montant'] ?? 0);
            $dejaPaye = (float) ($manquant['montant_paye'] ?? 0);
            $nouveauPaye = $total > 0 ? min($total, $dejaPaye + $montant) : ($dejaPaye + $montant);
            $reste = max(0, $total - $nouveauPaye);
            $statut = $reste <= 0.01 ? 'paye' : ($nouveauPaye > 0 ? 'partiel' : 'ouvert');

            $this->db->insert('manquant_paiements', [
                'manquant_id' => $id,
                'montant' => $montant,
                'date_paiement' => $datePaiement,
                'note' => $note,
                'created_by' => $createdBy
            ]);

            $this->update($id, [
                'montant_paye' => $nouveauPaye,
                'date_reglement' => $statut === 'paye' ? $datePaiement : null,
                'notes_reglement' => $note,
                'statut' => $statut
            ]);

            $this->db->commit();
            return ['success' => true, 'reste' => $reste, 'statut' => $statut];
        } catch (Exception $e) {
            if ($this->db->inTransaction()) {
                $this->db->rollBack();
            }
            return ['success' => false, 'message' => $e->getMessage()];
        }
    }
}
PHP);

writeFileUtf8($root . '/app/Controllers/ManquantController.php', <<<'PHP'
<?php

class ManquantController extends Controller
{
    private $model;

    public function __construct()
    {
        parent::__construct();
        $this->model = new Manquant();
    }

    public function index()
    {
        $this->requirePermission('pertes.voir');
        $filters = [
            'agent_id' => $_GET['agent_id'] ?? null,
            'produit_id' => $_GET['produit_id'] ?? null,
            'statut' => $_GET['statut'] ?? null,
            'date_debut' => $_GET['date_debut'] ?? date('Y-m-01'),
            'date_fin' => $_GET['date_fin'] ?? date('Y-m-d'),
        ];

        $rows = $this->model->getWithDetails($filters);
        if (isset($_GET['export'])) {
            return $this->exportRows($rows);
        }

        $this->view('manquants/index', [
            'manquants' => $rows,
            'resume' => $this->model->getSummaryByAgent($filters),
            'agents' => (new User())->getActive(),
            'produits' => (new Produit())->getActive(),
            'filters' => $filters,
            'print_mode' => isset($_GET['print']),
        ]);
    }

    public function create()
    {
        $this->requirePermission('pertes.creer');
        $this->view('manquants/create', [
            'agents' => (new User())->getActive(),
            'produits' => (new Produit())->getActive()
        ]);
    }

    public function store()
    {
        $this->requirePermission('pertes.creer');
        $data = $this->getJsonInput();
        $errors = $this->validate($data, [
            'agent_id' => 'required|numeric',
            'quantite_caisses' => 'required|numeric',
            'date_manquant' => 'required'
        ]);
        if ($errors) {
            return $this->error('Erreurs de validation', 422, $errors);
        }

        $data['produit_id'] = !empty($data['produit_id']) ? (int) $data['produit_id'] : null;
        $data['montant'] = max(0, (float) ($data['montant'] ?? 0));
        $data['montant_paye'] = max(0, (float) ($data['montant_paye'] ?? 0));
        $data['statut'] = $data['montant_paye'] >= $data['montant'] && $data['montant'] > 0
            ? 'paye'
            : ($data['montant_paye'] > 0 ? 'partiel' : 'ouvert');
        $data['created_by'] = $_SESSION['user_id'];

        $id = $this->model->create($data);
        return $this->success(['id' => $id], 'Manquant enregistré avec succès');
    }

    public function payer($id)
    {
        $this->requirePermission('pertes.creer');
        $data = $this->getJsonInput();
        $result = $this->model->enregistrerPaiement(
            (int) $id,
            $data['montant'] ?? 0,
            $data['date_paiement'] ?? date('Y-m-d'),
            trim($data['note'] ?? ''),
            $_SESSION['user_id'] ?? null
        );

        if ($result['success']) {
            return $this->success($result, 'Paiement enregistré');
        }
        return $this->error($result['message'], 400);
    }

    public function delete($id)
    {
        $this->requirePermission('pertes.creer');
        $this->model->delete($id);
        return $this->success(null, 'Manquant supprimé');
    }

    public function export()
    {
        $_GET['export'] = 1;
        $this->index();
    }

    private function exportRows($rows)
    {
        header('Content-Type: text/csv; charset=utf-8');
        header('Content-Disposition: attachment; filename=manquants_agents_' . date('Y-m-d_H-i') . '.csv');
        $out = fopen('php://output', 'w');
        fprintf($out, chr(0xEF) . chr(0xBB) . chr(0xBF));
        fputcsv($out, ['Date', 'Agent', 'Produit', 'Caisses', 'Montant', 'Payé', 'Reste', 'Statut', 'Motif']);
        foreach ($rows as $row) {
            fputcsv($out, [
                $row['date_manquant'],
                $row['agent_nom'],
                $row['produit_nom'] ?: '-',
                $row['quantite_caisses'],
                $row['montant'],
                $row['montant_paye'],
                $row['reste_montant'],
                $row['statut'],
                $row['motif']
            ]);
        }
        fclose($out);
        exit;
    }
}
PHP);

writeFileUtf8($root . '/app/Views/manquants/index.php', <<<'PHP'
<?php
$pageTitle = 'Manquants agents';
$printMode = !empty($print_mode);
$query = array_filter($filters, fn($v) => $v !== null && $v !== '');
$periodeLabel = date('d/m/Y', strtotime($filters['date_debut'])) . ' au ' . date('d/m/Y', strtotime($filters['date_fin']));
$totalMontant = array_sum(array_map(fn($m) => (float) ($m['montant'] ?? 0), $manquants));
$totalPaye = array_sum(array_map(fn($m) => (float) ($m['montant_paye'] ?? 0), $manquants));
$totalReste = array_sum(array_map(fn($m) => (float) ($m['reste_montant'] ?? 0), $manquants));
$customStyle = "
@media print {
    @page { size: A4 portrait; margin: 10mm; }
    aside, header, .no-print, .fixed, button, .btn { display: none !important; }
    main { margin: 0 !important; padding: 0 !important; width: 100% !important; }
    body { background: #fff !important; }
    .report-sheet { box-shadow: none !important; padding: 0 !important; }
    .print-table th, .print-table td { border: 1px solid #d1d5db !important; padding: 6px !important; font-size: 10px !important; }
}
.report-sheet { background: white; border-radius: 12px; box-shadow: 0 10px 30px rgba(15,23,42,.08); }
.print-table { width: 100%; border-collapse: collapse; }
.print-table th { background: #111827; color: white; text-align: left; font-size: 11px; text-transform: uppercase; }
.print-table td { border-bottom: 1px solid #e5e7eb; padding: 8px; }
";
ob_start();
?>
<div x-data="manquantsPage()" class="report-sheet p-4 md:p-6">
    <div class="flex flex-wrap items-center justify-between gap-4 mb-6 no-print">
        <div>
            <h1 class="text-2xl font-bold text-gray-900 dark:text-white">Manquants agents</h1>
            <p class="text-sm text-gray-500">Rapport détaillé, paiements et restes à payer par agent.</p>
        </div>
        <div class="flex gap-2">
            <?php if (can('pertes.creer')): ?><a href="<?= url('manquants/create') ?>" class="btn btn-primary">Enregistrer un manquant</a><?php endif; ?>
            <a href="?<?= http_build_query(array_merge($query, ['export' => 1])) ?>" class="btn btn-secondary">Exporter CSV</a>
            <button type="button" onclick="window.open('?<?= http_build_query(array_merge($query, ['print' => 1])) ?>','_blank')" class="btn btn-secondary">Imprimer</button>
        </div>
    </div>

    <div class="hidden print:block mb-6 border-b-2 border-gray-900 pb-4">
        <div class="flex justify-between items-start">
            <div>
                <h1 class="text-2xl font-bold uppercase"><?= htmlspecialchars((new Parametre())->get('nom_entreprise', APP_NAME)) ?></h1>
                <p class="text-sm text-gray-600">Rapport professionnel des manquants agents</p>
                <p class="text-sm text-gray-600">Période : <strong><?= htmlspecialchars($periodeLabel) ?></strong></p>
            </div>
            <div class="text-right text-xs text-gray-600">
                <p>Imprimé le <?= date('d/m/Y H:i') ?></p>
                <p>Utilisateur : <?= htmlspecialchars($_SESSION['user_prenom'] ?? '') ?> <?= htmlspecialchars($_SESSION['user_nom'] ?? '') ?></p>
            </div>
        </div>
    </div>

    <div class="card mb-6 no-print">
        <div class="card-body">
            <form method="GET" class="flex flex-wrap gap-3 items-end">
                <div><label class="label">Agent</label><select name="agent_id" class="input"><option value="">Tous</option><?php foreach ($agents as $a): ?><option value="<?= $a['id'] ?>" <?= ($filters['agent_id'] ?? '') == $a['id'] ? 'selected' : '' ?>><?= htmlspecialchars($a['prenom'].' '.$a['nom']) ?></option><?php endforeach; ?></select></div>
                <div><label class="label">Produit</label><select name="produit_id" class="input"><option value="">Tous</option><?php foreach ($produits as $p): ?><option value="<?= $p['id'] ?>" <?= ($filters['produit_id'] ?? '') == $p['id'] ? 'selected' : '' ?>><?= htmlspecialchars($p['nom']) ?></option><?php endforeach; ?></select></div>
                <div><label class="label">Statut</label><select name="statut" class="input"><option value="">Tous</option><option value="ouvert" <?= ($filters['statut'] ?? '') === 'ouvert' ? 'selected' : '' ?>>Ouvert</option><option value="partiel" <?= ($filters['statut'] ?? '') === 'partiel' ? 'selected' : '' ?>>Partiel</option><option value="paye" <?= ($filters['statut'] ?? '') === 'paye' ? 'selected' : '' ?>>Payé</option></select></div>
                <div><label class="label">Date début</label><input type="date" name="date_debut" value="<?= htmlspecialchars($filters['date_debut']) ?>" class="input"></div>
                <div><label class="label">Date fin</label><input type="date" name="date_fin" value="<?= htmlspecialchars($filters['date_fin']) ?>" class="input"></div>
                <button class="btn btn-primary">Filtrer</button><a href="<?= url('manquants') ?>" class="btn btn-secondary">Reset</a>
            </form>
        </div>
    </div>

    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <div class="stat-card"><p class="stat-label">Manquants</p><p class="stat-value"><?= count($manquants) ?></p></div>
        <div class="stat-card"><p class="stat-label">Montant total</p><p class="stat-value text-red-600"><?= format_money_converted($totalMontant) ?></p></div>
        <div class="stat-card"><p class="stat-label">Déjà payé</p><p class="stat-value text-green-600"><?= format_money_converted($totalPaye) ?></p></div>
        <div class="stat-card"><p class="stat-label">Reste à payer</p><p class="stat-value text-orange-600"><?= format_money_converted($totalReste) ?></p></div>
    </div>

    <?php if (!empty($resume)): ?>
    <div class="mb-6">
        <h2 class="text-sm font-bold uppercase text-gray-500 mb-2">Résumé par agent</h2>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
            <?php foreach ($resume as $r): ?>
            <div class="rounded-lg border border-gray-200 p-3">
                <p class="font-bold"><?= htmlspecialchars($r['agent_nom']) ?></p>
                <p class="text-sm text-gray-500"><?= (int) $r['nombre'] ?> cas · <?= number_format((float) $r['total_caisses'], 2, ',', ' ') ?> cs</p>
                <p class="text-sm">Payé: <strong class="text-green-600"><?= format_money_converted($r['total_paye']) ?></strong></p>
                <p class="text-sm">Reste: <strong class="text-orange-600"><?= format_money_converted($r['total_reste']) ?></strong></p>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
    <?php endif; ?>

    <div class="overflow-x-auto">
        <table class="print-table">
            <thead><tr><th>Date</th><th>Agent</th><th>Produit</th><th class="text-right">Caisses</th><th class="text-right">Montant</th><th class="text-right">Payé</th><th class="text-right">Reste</th><th>Statut</th><th>Motif</th><th class="no-print"></th></tr></thead>
            <tbody>
            <?php if (!$manquants): ?><tr><td colspan="10" class="text-center py-8 text-gray-500">Aucun manquant trouvé.</td></tr><?php endif; ?>
            <?php foreach ($manquants as $m): ?>
                <?php $reste = (float) ($m['reste_montant'] ?? 0); $statut = $m['statut'] === 'regle' ? 'paye' : $m['statut']; ?>
                <tr>
                    <td><?= date('d/m/Y', strtotime($m['date_manquant'])) ?></td>
                    <td class="font-semibold"><?= htmlspecialchars($m['agent_nom']) ?></td>
                    <td><?= htmlspecialchars($m['produit_nom'] ?: '-') ?></td>
                    <td class="text-right font-bold"><?= number_format((float) $m['quantite_caisses'], 2, ',', ' ') ?></td>
                    <td class="text-right font-bold"><?= format_money_converted($m['montant']) ?></td>
                    <td class="text-right text-green-700 font-bold"><?= format_money_converted($m['montant_paye'] ?? 0) ?></td>
                    <td class="text-right text-orange-700 font-bold"><?= format_money_converted($reste) ?></td>
                    <td><?= $statut === 'paye' ? 'Payé' : ($statut === 'partiel' ? 'Partiel' : 'Ouvert') ?></td>
                    <td><?= htmlspecialchars($m['motif'] ?: '-') ?></td>
                    <td class="no-print text-right whitespace-nowrap">
                        <?php if (can('pertes.creer') && $reste > 0.01): ?>
                        <button type="button" @click="openPayment(<?= (int) $m['id'] ?>, '<?= htmlspecialchars($m['agent_nom'], ENT_QUOTES) ?>', <?= (float) $reste ?>)" class="text-green-600 hover:text-green-800 mr-3" title="Régler">
                            <svg class="w-5 h-5 inline" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8V6m0 12v-2m9-4a9 9 0 11-18 0 9 9 0 0118 0z"/></svg>
                        </button>
                        <?php endif; ?>
                        <?php if (can('pertes.creer')): ?>
                        <button type="button" @click="removeManquant(<?= (int) $m['id'] ?>)" class="text-red-600 hover:text-red-800" title="Supprimer">
                            <svg class="w-5 h-5 inline" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
                        </button>
                        <?php endif; ?>
                    </td>
                </tr>
            <?php endforeach; ?>
            </tbody>
        </table>
    </div>

    <div x-show="payment.open" class="fixed inset-0 z-50 flex items-center justify-center p-4 no-print" style="display:none">
        <div class="absolute inset-0 bg-black/50" @click="payment.open=false"></div>
        <div class="relative bg-white dark:bg-gray-800 rounded-xl shadow-xl w-full max-w-md p-6">
            <h3 class="text-lg font-bold mb-1">Régler un manquant</h3>
            <p class="text-sm text-gray-500 mb-4" x-text="payment.agent + ' · reste: ' + App.formatMoneyConverted(payment.reste, (window.BASE_DEVISE || 'CDF'), window.DEVISE)"></p>
            <div class="space-y-3">
                <div><label class="label">Montant payé</label><input type="number" min="0.01" step="0.01" x-model.number="payment.montant" class="input"></div>
                <div><label class="label">Date paiement</label><input type="date" x-model="payment.date_paiement" class="input"></div>
                <div><label class="label">Note</label><textarea x-model="payment.note" class="input" rows="2"></textarea></div>
            </div>
            <div class="mt-5 flex justify-end gap-2">
                <button type="button" class="btn btn-secondary" @click="payment.open=false">Annuler</button>
                <button type="button" class="btn btn-primary" @click="savePayment()" :disabled="loading">Enregistrer</button>
            </div>
        </div>
    </div>
</div>

<script>
function manquantsPage() {
    return {
        loading: false,
        payment: { open: false, id: null, agent: '', reste: 0, montant: 0, date_paiement: new Date().toISOString().slice(0, 10), note: '' },
        openPayment(id, agent, reste) {
            this.payment = { open: true, id, agent, reste, montant: reste, date_paiement: new Date().toISOString().slice(0, 10), note: '' };
        },
        async savePayment() {
            this.loading = true;
            try {
                await App.api('/api/manquants/' + this.payment.id + '/paiement', 'POST', {
                    montant: this.payment.montant,
                    date_paiement: this.payment.date_paiement,
                    note: this.payment.note
                });
                App.notify('Paiement enregistré', 'success');
                location.reload();
            } catch (e) {
                App.notify(e.message || 'Erreur lors du paiement', 'error');
            } finally {
                this.loading = false;
            }
        },
        async removeManquant(id) {
            const ok = await App.confirm({ title: 'Supprimer ?', message: 'Supprimer ce manquant ?', confirmText: 'Supprimer', cancelText: 'Annuler', type: 'danger' });
            if (!ok) return;
            await App.api('/api/manquants/' + id, 'DELETE');
            location.reload();
        }
    }
}
</script>
<?php if ($printMode): ?><script>window.addEventListener('load', () => window.print());</script><?php endif; ?>
<?php $content = ob_get_clean(); require ROOT_PATH . '/app/Views/layouts/app.php'; ?>
PHP);

writeFileUtf8($root . '/app/Views/manquants/create.php', <<<'PHP'
<?php $pageTitle = 'Enregistrer un manquant'; ob_start(); ?>
<div class="mb-6">
    <a href="<?= url('manquants') ?>" class="text-primary-600 hover:text-primary-700 flex items-center gap-2">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18"/></svg>
        Retour aux manquants
    </a>
</div>
<div class="max-w-2xl mx-auto">
    <div class="card">
        <div class="card-header"><h2 class="text-lg font-semibold">Nouveau manquant agent</h2></div>
        <div class="card-body">
            <form x-data="manquantForm" @submit.prevent="save" class="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div><label class="label">Agent *</label><select x-model="form.agent_id" class="input" required><option value="">Sélectionner</option><?php foreach($agents as $a): ?><option value="<?= $a['id'] ?>"><?= htmlspecialchars($a['prenom'].' '.$a['nom']) ?></option><?php endforeach; ?></select></div>
                <div><label class="label">Produit concerné</label><select x-model="form.produit_id" class="input"><option value="">Aucun / montant seul</option><?php foreach($produits as $p): ?><option value="<?= $p['id'] ?>"><?= htmlspecialchars($p['nom']) ?></option><?php endforeach; ?></select></div>
                <div><label class="label">Quantité manquante (caisses) *</label><input type="number" min="0" step="0.01" x-model.number="form.quantite_caisses" class="input" required></div>
                <div><label class="label">Montant à payer</label><input type="number" min="0" step="0.01" x-model.number="form.montant" class="input"></div>
                <div><label class="label">Montant déjà payé</label><input type="number" min="0" step="0.01" x-model.number="form.montant_paye" class="input"></div>
                <div><label class="label">Date *</label><input type="date" x-model="form.date_manquant" class="input" required></div>
                <div class="md:col-span-2"><label class="label">Motif / observation</label><textarea x-model="form.motif" class="input" rows="3"></textarea></div>
                <div class="md:col-span-2 flex justify-end gap-2"><a href="<?= url('manquants') ?>" class="btn btn-secondary">Annuler</a><button class="btn btn-primary" :disabled="loading">Enregistrer</button></div>
            </form>
        </div>
    </div>
</div>
<script>
document.addEventListener('alpine:init', () => Alpine.data('manquantForm', () => ({
    loading: false,
    form: { agent_id: '', produit_id: '', quantite_caisses: 0, montant: 0, montant_paye: 0, date_manquant: new Date().toISOString().slice(0,10), motif: '' },
    async save() {
        this.loading = true;
        try {
            await App.api('/api/manquants', 'POST', this.form);
            App.notify('Manquant enregistré', 'success');
            setTimeout(() => location.href = '<?= url('manquants') ?>', 600);
        } catch (e) {
            App.notify(e.message, 'error');
            this.loading = false;
        }
    }
})));
</script>
<?php $content = ob_get_clean(); require ROOT_PATH . '/app/Views/layouts/app.php'; ?>
PHP);

$migration = <<<'SQL'
ALTER TABLE manquants_agents
  ADD COLUMN IF NOT EXISTS montant_paye DECIMAL(15,2) NOT NULL DEFAULT 0 AFTER montant,
  ADD COLUMN IF NOT EXISTS date_reglement DATE DEFAULT NULL AFTER date_manquant,
  ADD COLUMN IF NOT EXISTS notes_reglement TEXT DEFAULT NULL AFTER motif,
  MODIFY statut ENUM('ouvert','partiel','paye','regle') NOT NULL DEFAULT 'ouvert';

CREATE TABLE IF NOT EXISTS manquant_paiements (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  manquant_id INT UNSIGNED NOT NULL,
  montant DECIMAL(15,2) NOT NULL DEFAULT 0,
  date_paiement DATE NOT NULL,
  note TEXT DEFAULT NULL,
  created_by INT UNSIGNED DEFAULT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_manquant_paiements_manquant (manquant_id),
  CONSTRAINT fk_manquant_paiements_manquant FOREIGN KEY (manquant_id) REFERENCES manquants_agents(id) ON DELETE CASCADE,
  CONSTRAINT fk_manquant_paiements_user FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE manquants_agents
SET montant_paye = CASE WHEN statut = 'regle' THEN montant ELSE montant_paye END,
    statut = CASE WHEN statut = 'regle' THEN 'paye' ELSE statut END
WHERE statut = 'regle';
SQL;
writeFileUtf8($root . '/database/migration_2026_06_06_manquants_paiements_interchange.sql', $migration);

$publicIndex = $root . '/public/index.php';
if (strpos(file_get_contents($publicIndex), "/api/manquants/(\\d+)/paiement") === false) {
    replaceOnce(
        $publicIndex,
        "    'DELETE::/api/manquants/(\\d+)' => ['ManquantController', 'delete'],\n",
        "    'DELETE::/api/manquants/(\\d+)' => ['ManquantController', 'delete'],\n    'POST::/api/manquants/(\\d+)/paiement' => ['ManquantController', 'payer'],\n"
    );
}

$adminController = $root . '/app/Controllers/AdminController.php';
replaceOnce(
    $adminController,
    "            'devise', 'taux_change', 'taux_tva'\n",
    "            'devise', 'taux_change', 'taux_tva', 'autoriser_interchange_emballages'\n"
);

$parametre = $root . '/app/Models/Parametre.php';
replaceOnce(
    $parametre,
    "            'taux_tva' => \$this->get('taux_tva', '16')\n",
    "            'taux_tva' => \$this->get('taux_tva', '16'),\n            'autoriser_interchange_emballages' => \$this->get('autoriser_interchange_emballages', '1')\n"
);

$settings = $root . '/app/Views/admin/settings.php';
replaceOnce(
    $settings,
    "                    <div>\n                        <label class=\"label\">Couleur primaire</label>",
    "                    <div>\n                        <label class=\"label\">Interchange des emballages</label>\n                        <select x-model=\"params.autoriser_interchange_emballages\" class=\"input\">\n                            <option value=\"1\">Autoriser l'interchange</option>\n                            <option value=\"0\">Refuser l'interchange</option>\n                        </select>\n                        <p class=\"text-xs text-gray-500 mt-1\">Si refusé, les emballages reçus seront saisis produit par produit dans la vente.</p>\n                    </div>\n                    <div>\n                        <label class=\"label\">Couleur primaire</label>"
);
replaceOnce(
    $settings,
    "            taux_tva: <?= floatval(\$params['taux_tva'] ?? 16) ?>,\n            couleur_primaire:",
    "            taux_tva: <?= floatval(\$params['taux_tva'] ?? 16) ?>,\n            autoriser_interchange_emballages: '<?= htmlspecialchars(\$params['autoriser_interchange_emballages'] ?? '1') ?>',\n            couleur_primaire:"
);

$venteController = $root . '/app/Controllers/VenteController.php';
replaceOnce(
    $venteController,
    "        \$tva = \$this->parametreModel->get('taux_tva', 16);\n        \n        \$this->view('ventes/create', [",
    "        \$tva = \$this->parametreModel->get('taux_tva', 16);\n        \$autoriserInterchangeEmballages = \$this->parametreModel->get('autoriser_interchange_emballages', '1') === '1';\n        \n        \$this->view('ventes/create', ["
);
replaceOnce(
    $venteController,
    "            'numero_facture' => \$this->venteModel->generateNumeroFacture()\n",
    "            'numero_facture' => \$this->venteModel->generateNumeroFacture(),\n            'autoriser_interchange_emballages' => \$autoriserInterchangeEmballages\n"
);
replaceOnce(
    $venteController,
    "        \$emballagesRecus = \$this->normaliserEmballagesRecus(\$data['emballages_recus'] ?? null);\n",
    "        \$autoriserInterchangeEmballages = \$this->parametreModel->get('autoriser_interchange_emballages', '1') === '1';\n        \$emballagesRecus = \$autoriserInterchangeEmballages ? \$this->normaliserEmballagesRecus(\$data['emballages_recus'] ?? null) : [];\n"
);

$venteView = $root . '/app/Views/ventes/create.php';
replaceOnce($venteView, "ob_start();\n?>", "\$autoriserInterchangeEmballages = !empty(\$autoriser_interchange_emballages);\nob_start();\n?>");
replaceOnce(
    $venteView,
    "<th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase\">Caisses</th>\n                                    <th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase\">Sous-total</th>",
    "<th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase\">Caisses</th>\n                                    <?php if (!\$autoriserInterchangeEmballages): ?><th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase\">Emballages reçus</th><?php endif; ?>\n                                    <th class=\"px-4 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase\">Sous-total</th>"
);
replaceOnce(
    $venteView,
    "<input type=\"number\" x-model.number=\"ligne.caisses\" class=\"input w-24\" min=\"1\" step=\"1\" required @input=\"ligne.caisses = Math.round(ligne.caisses || 0); calculateTotals()\">\n                                        </td>\n                                        <td class=\"px-4 py-2 text-sm font-medium\">",
    "<input type=\"number\" x-model.number=\"ligne.caisses\" class=\"input w-24\" min=\"1\" step=\"1\" required @input=\"ligne.caisses = Math.round(ligne.caisses || 0); calculateTotals()\">\n                                        </td>\n                                        <?php if (!\$autoriserInterchangeEmballages): ?>\n                                        <td class=\"px-4 py-2\">\n                                            <input type=\"number\" x-model.number=\"ligne.caisses_vides_recues\" class=\"input w-28\" min=\"0\" step=\"1\" @input=\"ligne.caisses_vides_recues = Math.max(0, Math.round(ligne.caisses_vides_recues || 0))\">\n                                        </td>\n                                        <?php endif; ?>\n                                        <td class=\"px-4 py-2 text-sm font-medium\">"
);
replaceOnce(
    $venteView,
    "                <!-- Emballages recus -->",
    "                <?php if (\$autoriserInterchangeEmballages): ?>\n                <!-- Emballages reçus -->"
);
replaceOnce(
    $venteView,
    "                </div>\n                \n                <!-- Billetage -->",
    "                </div>\n                <?php endif; ?>\n                \n                <!-- Billetage -->"
);
replaceOnce(
    $venteView,
    "        lignes: [{ produit_id: '', caisses: 0, prix_caisse: 0 }],",
    "        lignes: [{ produit_id: '', caisses: 0, caisses_vides_recues: 0, prix_caisse: 0 }],"
);
replaceOnce(
    $venteView,
    "        emballages_recus: {},",
    "        emballages_recus: {},\n        autoriserInterchange: <?= \$autoriserInterchangeEmballages ? 'true' : 'false' ?>,"
);
replaceOnce(
    $venteView,
    "            return Object.values(this.emballages_recus || {}).reduce((sum, value) => {\n                return sum + Math.max(0, Math.round(parseFloat(value) || 0));\n            }, 0);",
    "            if (!this.autoriserInterchange) {\n                return (this.lignes || []).reduce((sum, ligne) => sum + Math.max(0, Math.round(parseFloat(ligne.caisses_vides_recues) || 0)), 0);\n            }\n            return Object.values(this.emballages_recus || {}).reduce((sum, value) => {\n                return sum + Math.max(0, Math.round(parseFloat(value) || 0));\n            }, 0);"
);
replaceOnce(
    $venteView,
    "            return Object.entries(this.emballages_recus || {})",
    "            if (!this.autoriserInterchange) return [];\n            return Object.entries(this.emballages_recus || {})"
);
replaceOnce(
    $venteView,
    "                if (this.totalEmballagesRecus() > this.totalCaissesVendues()) {\n                    throw new Error('Le total des emballages recus ne peut pas depasser le total des caisses vendues.');\n                }\n",
    "                if (this.totalEmballagesRecus() > this.totalCaissesVendues()) {\n                    throw new Error('Le total des emballages reçus ne peut pas dépasser le total des caisses vendues.');\n                }\n                if (!this.autoriserInterchange) {\n                    const ligneInvalide = detailsLignes.find(l => Math.max(0, Math.round(parseFloat(l.caisses_vides_recues) || 0)) > Math.max(0, Math.round(parseFloat(l.caisses) || 0)));\n                    if (ligneInvalide) throw new Error('Les emballages reçus ne peuvent pas dépasser les caisses vendues sur une ligne.');\n                }\n"
);
replaceOnce(
    $venteView,
    "                        caisses_vides_recues: 0,",
    "                        caisses_vides_recues: this.autoriserInterchange ? 0 : Math.max(0, Math.round(parseFloat(l.caisses_vides_recues) || 0)),"
);
replaceOnce(
    $venteView,
    "                    emballages_recus: emballagesRecus,",
    "                    emballages_recus: this.autoriserInterchange ? emballagesRecus : [],"
);

echo "Modifications applied\n";
