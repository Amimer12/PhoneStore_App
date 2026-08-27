// supabase/functions/monthly-archive/index.ts
//
// Runs once a month (scheduled via pg_cron — see the snippet at the bottom
// of monthly_archive.sql) and does, in order:
//
//   1. Calls archive_month() to atomically copy last month's achats /
//      achat_items / depenses into the *_history tables and purge them
//      from the live tables. This step alone satisfies "the phone app
//      only ever sees the current month" — everything after this point is
//      just about producing the human-readable Excel copy, and if it
//      fails, the data is still safe in the history tables (nothing is
//      lost, the export can just be re-run).
//   2. Reads that month back OUT of the history tables (guaranteed to be
//      there now) and builds a 3-sheet workbook: Ventes (line-item
//      detail), Résumé (headline KPIs), Dépenses.
//   3. Uploads it to Google Drive, into "<root folder>/<year>/<year>-<month>.xlsx".
//      Re-running for a month that was already exported overwrites the
//      same file rather than duplicating it.
//
// Required secrets (set with `supabase secrets set NAME=value`):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   — auto-provided by Supabase
//   GDRIVE_SERVICE_ACCOUNT_JSON               — see _shared/drive.ts
//   GDRIVE_ARCHIVE_FOLDER_ID                  — see _shared/drive.ts
//   CRON_SECRET                               — any random string; the
//     pg_cron job must send it back as `x-cron-secret` so this endpoint
//     can't be triggered by a random request off the internet (the
//     function itself is deployed publicly reachable, like all Supabase
//     Edge Functions by default).
//
// Manual test / backfill: this function also accepts an optional JSON
// body { "year": 2026, "month": 7 } to archive a specific month instead
// of "last month" — handy for the one-time backfill mentioned at the
// bottom of monthly_archive.sql.

import { createClient } from 'npm:@supabase/supabase-js@2';
import ExcelJS from 'npm:exceljs@4.4.0';
import { driveAccessToken, ensureYearFolder, uploadXlsx } from '../_shared/drive.ts';
import { corsHeaders } from '../_shared/cors.ts';

function previousMonth(): { year: number; month: number } {
  const now = new Date();
  const y = now.getUTCFullYear();
  const m = now.getUTCMonth(); // 0-based; "last month" relative to now
  return m === 0 ? { year: y - 1, month: 12 } : { year: y, month: m };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const cronSecret = Deno.env.get('CRON_SECRET');
  if (cronSecret && req.headers.get('x-cron-secret') !== cronSecret) {
    return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401, headers: corsHeaders });
  }

  let year: number, month: number;
  try {
    const body = req.headers.get('content-length') !== '0' ? await req.json().catch(() => ({})) : {};
    const target = body?.year && body?.month ? { year: body.year, month: body.month } : previousMonth();
    year = target.year;
    month = target.month;
  } catch {
    const target = previousMonth();
    year = target.year;
    month = target.month;
  }

  const supabase = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const monthLabel = `${year}-${String(month).padStart(2, '0')}`;

  try {
    // Step 1 — atomic archive + purge. If a previous run already archived
    // this month, the ON CONFLICT DO NOTHING inside archive_month() means
    // this is a harmless no-op (counts will just come back as 0), not an
    // error — safe to re-run.
    const { data: archiveResult, error: archiveError } = await supabase.rpc('archive_month', {
      p_year: year,
      p_month: month,
    });
    if (archiveError) throw new Error(`archive_month failed: ${archiveError.message}`);

    // Step 2 — read the now-archived month back out, plus the (small,
    // rarely-changing) dimension tables needed to turn ids into readable
    // labels for the spreadsheet.
    const [{ data: items, error: itemsErr }, { data: achats, error: achatsErr }, { data: depenses, error: depensesErr },
      { data: products }, { data: categories }, { data: types }, { data: marques }] = await Promise.all([
      supabase.from('achat_items_history').select('*').eq('archived_month', monthLabel),
      supabase.from('achats_history').select('*').eq('archived_month', monthLabel),
      supabase.from('depenses_history').select('*').eq('archived_month', monthLabel),
      supabase.from('products').select('id, name, reference, marque_id, type1_id'),
      supabase.from('categories').select('id, name'),
      supabase.from('product_types').select('id, name'),
      supabase.from('marques').select('id, name'),
    ]);
    if (itemsErr) throw itemsErr;
    if (achatsErr) throw achatsErr;
    if (depensesErr) throw depensesErr;

    const byId = <T extends { id: number }>(rows: T[] | null) => new Map((rows ?? []).map((r) => [r.id, r]));
    const productsById = byId(products ?? []);
    const categoriesById = byId(categories ?? []);
    const typesById = byId(types ?? []);
    const marquesById = byId(marques ?? []);

    const labelFor = (row: any) => {
      if (row.product_id) {
        const p = productsById.get(row.product_id);
        const marque = p?.marque_id ? marquesById.get(p.marque_id)?.name : null;
        const type1 = p?.type1_id ? typesById.get(p.type1_id)?.name : null;
        return [marque, type1, p?.name].filter(Boolean).join(' ') || p?.reference || `Produit #${row.product_id}`;
      }
      return row.label || 'Service';
    };

    // Step 3 — build the workbook.
    const wb = new ExcelJS.Workbook();
    wb.creator = 'PhoneStore — export automatique';
    wb.created = new Date();

    // --- Résumé ---
    const grossRevenue = (items ?? []).reduce((s, i: any) => s + (i.subtotal ?? 0), 0);
    const totalCost = (items ?? []).reduce((s, i: any) => s + (i.cost_subtotal ?? 0), 0);
    const netRevenue = grossRevenue - totalCost;
    const totalDepenses = (depenses ?? []).reduce((s, d: any) => s + d.prix, 0);
    const netProfitAfterDepenses = netRevenue - totalDepenses;
    const salesCount = achats?.length ?? 0;
    const avgBasket = salesCount ? Math.round(grossRevenue / salesCount) : 0;

    const revenueByCategory = new Map<string, number>();
    for (const i of items ?? []) {
      const catName = i.category_id ? categoriesById.get(i.category_id)?.name ?? 'Autre' : 'Autre';
      revenueByCategory.set(catName, (revenueByCategory.get(catName) ?? 0) + (i.subtotal ?? 0));
    }
    const topCategories = [...revenueByCategory.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);

    const summary = wb.addWorksheet('Résumé');
    summary.columns = [{ width: 32 }, { width: 20 }];
    summary.addRows([
      [`Résumé — ${monthLabel}`],
      [],
      ['Chiffre d’affaires brut (DA)', grossRevenue],
      ['Coût des ventes (DA)', totalCost],
      ['Revenu net / marge (DA)', netRevenue],
      ['Dépenses (DA)', totalDepenses],
      ['Bénéfice net après dépenses (DA)', netProfitAfterDepenses],
      ['Nombre de ventes', salesCount],
      ['Panier moyen (DA)', avgBasket],
      [],
      ['Top 5 catégories par revenu'],
      ...topCategories.map(([name, revenue]) => [name, revenue]),
    ]);
    summary.getRow(1).font = { bold: true, size: 14 };
    summary.getRow(11).font = { bold: true };

    // --- Ventes (line-item detail) ---
    const ventes = wb.addWorksheet('Ventes');
    ventes.columns = [
      { header: 'Date', key: 'date', width: 12 },
      { header: 'Heure', key: 'heure', width: 10 },
      { header: 'Vente #', key: 'achat_id', width: 10 },
      { header: 'Article', key: 'article', width: 32 },
      { header: 'Catégorie', key: 'categorie', width: 18 },
      { header: 'Type', key: 'is_repair', width: 14 },
      { header: 'Qté', key: 'quantite', width: 8 },
      { header: 'Prix unitaire', key: 'prix_unitaire', width: 14 },
      { header: 'Coût unitaire', key: 'cout_unitaire', width: 14 },
      { header: 'Sous-total (DA)', key: 'sous_total', width: 16 },
      { header: 'Marge (DA)', key: 'marge', width: 14 },
    ];
    ventes.getRow(1).font = { bold: true };
    for (const i of (items ?? []) as any[]) {
      ventes.addRow({
        date: i.achat_date,
        heure: i.achat_time,
        achat_id: i.achat_id,
        article: labelFor(i),
        categorie: i.category_id ? categoriesById.get(i.category_id)?.name ?? '' : '',
        is_repair: i.product_id ? 'Produit' : 'Réparation',
        quantite: i.quantity,
        prix_unitaire: i.unit_price,
        cout_unitaire: i.unit_cost ?? '',
        sous_total: i.subtotal ?? 0,
        marge: (i.subtotal ?? 0) - (i.cost_subtotal ?? 0),
      });
    }

    // --- Dépenses ---
    const dep = wb.addWorksheet('Dépenses');
    dep.columns = [
      { header: 'Date', key: 'date', width: 14 },
      { header: 'Nom', key: 'name', width: 32 },
      { header: 'Montant (DA)', key: 'prix', width: 16 },
    ];
    dep.getRow(1).font = { bold: true };
    for (const d of (depenses ?? []) as any[]) {
      dep.addRow({ date: d.depense_date, name: d.name, prix: d.prix });
    }

    const buffer = await wb.xlsx.writeBuffer();

    // Step 4 — upload to Drive.
    const rootFolderId = Deno.env.get('GDRIVE_ARCHIVE_FOLDER_ID');
    let driveLink: string | null = null;
    if (rootFolderId) {
      const token = await driveAccessToken();
      const yearFolderId = await ensureYearFolder(token, rootFolderId, year);
      const uploaded = await uploadXlsx(token, yearFolderId, `${monthLabel}.xlsx`, new Uint8Array(buffer as ArrayBuffer));
      driveLink = uploaded.webViewLink;
    }

    return new Response(
      JSON.stringify({
        month: monthLabel,
        archived: archiveResult?.[0] ?? null,
        gross_revenue: grossRevenue,
        net_revenue: netRevenue,
        net_profit_after_depenses: netProfitAfterDepenses,
        drive_link: driveLink,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (err) {
    console.error('monthly-archive failed:', err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: corsHeaders });
  }
});
