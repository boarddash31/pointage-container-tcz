import { createClient } from 'npm:@supabase/supabase-js@2.76.1';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';
import { terminalSlipPdf } from './terminal-slip.ts';
import { documentPdfPath,hasCurrentPdf,isTerminalForm,terminalTemplateVersion } from './pdf-cache.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
  'Access-Control-Allow-Methods': 'POST,OPTIONS',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'content-type': 'application/json' },
  });

function printable(input: unknown, fallback = '-', maxLength = 110): string {
  if (input === null || input === undefined || String(input).trim() === '') return fallback;
  return String(input)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\x20-\x7E]/g, '')
    .slice(0, maxLength);
}

function formatDate(rawIso: unknown): string {
  if (!rawIso) return '-';
  try {
    const s = String(rawIso);
    const d = new Date(s);
    if (isNaN(d.getTime())) return s.split('.')[0].replace('T', ' ');
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${pad(d.getUTCDate())}/${pad(d.getUTCMonth() + 1)}/${d.getUTCFullYear()} a ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
  } catch {
    return String(rawIso);
  }
}

async function pdfFor(document: Record<string, unknown>): Promise<Uint8Array> {
  if (['ENTREE','DEPOSE','PRISE','SORTIE'].includes(String(document.kind).toUpperCase())) return terminalSlipPdf(document);
  const snapshot = (document.snapshot ?? {}) as Record<string, unknown>;
  const event = (snapshot.event ?? {}) as Record<string, unknown>;

  // A5 dimensions: width 419.53 pt, height 595.28 pt
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([419.53, 595.28]);

  const normal = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);

  const navy = rgb(0.027, 0.224, 0.353); // #075a8d
  const ink = rgb(0.06, 0.09, 0.16); // #0f172a
  const muted = rgb(0.39, 0.45, 0.55); // #64748b
  const borderGray = rgb(0.8, 0.84, 0.88); // #cbd5e1
  const lightBg = rgb(0.97, 0.98, 0.99); // #f8fafc
  const amber = rgb(0.85, 0.47, 0.02); // #d97706
  const green = rgb(0.09, 0.64, 0.29); // #16a34a

  const type = String(document.kind ?? 'ENTREE').toUpperCase();
  const title: Record<string, string> = {
    ENTREE: "BON D'ENTREE (GATE-IN)",
    SORTIE: 'BON DE SORTIE (GATE-OUT)',
  };

  const entryKind = String(snapshot.entry_kind ?? 'empty').toLowerCase();
  const rawContainer = event.container ?? snapshot.container_number;
  const containerStr = printable(
    rawContainer,
    entryKind === 'empty' ? 'EN ATTENTE CHARGEMENT (PRISE)' : 'NON RENSEIGNE'
  );

  const rawBooking = event.booking ?? snapshot.booking;
  const bookingStr = printable(
    rawBooking,
    entryKind === 'loaded' ? 'DEPOSE DIRECTE' : 'NON REQUIS'
  );

  // 1. Header: Terminal Conteneurs Zenata
  page.drawText('TCZ', { x: 20, y: 562, font: bold, size: 20, color: navy });
  page.drawText('TERMINAL CONTENEURS ZENATA', { x: 20, y: 550, font: bold, size: 7, color: navy });
  page.drawText('TCZ ZENATA - GUICHET UNIQUE & CONTROLE D\'ACCES', { x: 20, y: 541, font: normal, size: 5.5, color: muted });

  // Document Title Pill
  const docTitle = title[type] ?? `BON TCZ - ${type}`;
  page.drawRectangle({
    x: 230,
    y: 540,
    width: 170,
    height: 34,
    color: type === 'SORTIE' ? green : navy,
  });
  page.drawText(docTitle, { x: 238, y: 560, font: bold, size: 9.5, color: rgb(1, 1, 1) });
  page.drawText(`Ref: #${printable(document.id).slice(0, 8).toUpperCase()}`, { x: 238, y: 549, font: bold, size: 7, color: rgb(1, 1, 1) });
  page.drawText(`Date: ${formatDate(document.created_at)}`, { x: 238, y: 542, font: normal, size: 6.5, color: rgb(1, 1, 1) });

  page.drawLine({ start: { x: 20, y: 532 }, end: { x: 400, y: 532 }, thickness: 1, color: navy });

  // 2. Section: Transport & Chauffeur
  page.drawRectangle({
    x: 20,
    y: 476,
    width: 380,
    height: 50,
    color: lightBg,
    borderColor: borderGray,
    borderWidth: 0.8,
  });

  page.drawText('TRACTEUR / CAMION', { x: 28, y: 514, font: bold, size: 6.5, color: muted });
  page.drawRectangle({
    x: 28,
    y: 486,
    width: 90,
    height: 22,
    color: rgb(1, 1, 1),
    borderColor: navy,
    borderWidth: 1.2,
  });
  page.drawText(printable(snapshot.plate), { x: 34, y: 494, font: bold, size: 10, color: navy });

  page.drawText('CIN CHAUFFEUR', { x: 130, y: 514, font: bold, size: 6.5, color: muted });
  page.drawText(printable(snapshot.driver_cin), { x: 130, y: 495, font: bold, size: 9.5, color: ink });

  page.drawText('LIGNE MARITIME', { x: 220, y: 514, font: bold, size: 6.5, color: muted });
  page.drawText(printable(snapshot.armateur_id), { x: 220, y: 495, font: bold, size: 9.5, color: navy });

  page.drawText('NO. VISITE', { x: 310, y: 514, font: bold, size: 6.5, color: muted });
  page.drawText(`${printable(document.visit_id).slice(0, 8)}...`, { x: 310, y: 495, font: bold, size: 8, color: muted });

  // 3. Section: Details Conteneur (Direct Entree - Sortie sans yard)
  let yTable = 458;
  page.drawText('DETAILS OPERATIONNELS & CONTENEUR', { x: 20, y: yTable, font: bold, size: 7.5, color: navy });
  yTable -= 14;

  const tableHeaders = ['CONTENEUR ISO 6346', 'CODE ISO', 'OPERATION', 'BOOKING / REF', 'STATUT ENTREE'];
  const tableValues = [
    containerStr,
    printable(snapshot.iso_code),
    type,
    bookingStr,
    entryKind === 'loaded' ? 'Plein (Depose)' : 'Vide (Prise)',
  ];

  // Header row
  page.drawRectangle({ x: 20, y: yTable - 4, width: 380, height: 16, color: rgb(0.93, 0.95, 0.97) });
  const colX = [26, 130, 185, 255, 340];
  for (let i = 0; i < tableHeaders.length; i++) {
    page.drawText(tableHeaders[i], { x: colX[i], y: yTable + 1, font: bold, size: 6, color: ink });
  }

  // Data row
  yTable -= 18;
  page.drawRectangle({ x: 20, y: yTable - 4, width: 380, height: 18, color: rgb(1, 1, 1), borderColor: borderGray, borderWidth: 0.6 });
  for (let i = 0; i < tableValues.length; i++) {
    page.drawText(tableValues[i], {
      x: colX[i],
      y: yTable + 1,
      font: i === 0 ? bold : normal,
      size: i === 0 ? 8 : 7,
      color: i === 0 ? (rawContainer ? navy : amber) : ink,
    });
  }

  // 4. Section: Visual Schema & Gate-out Security Rules
  const yBox = yTable - 110;
  page.drawRectangle({
    x: 20,
    y: yBox,
    width: 380,
    height: 98,
    color: lightBg,
    borderColor: borderGray,
    borderWidth: 0.8,
  });

  // Vector Truck Drawing
  page.drawRectangle({ x: 30, y: yBox + 22, width: 140, height: 60, color: rgb(1, 1, 1), borderColor: borderGray, borderWidth: 0.5 });
  // Cabin
  page.drawRectangle({ x: 38, y: yBox + 36, width: 26, height: 32, color: navy });
  page.drawRectangle({ x: 50, y: yBox + 50, width: 12, height: 14, color: rgb(0.85, 0.92, 0.98) });
  // Chassis
  page.drawRectangle({ x: 64, y: yBox + 36, width: 94, height: 8, color: rgb(0.3, 0.35, 0.4) });
  // Container or Empty Platform
  if (entryKind === 'loaded') {
    page.drawRectangle({ x: 68, y: yBox + 44, width: 88, height: 28, color: rgb(0.88, 0.45, 0.15) });
    page.drawText('40\' HC', { x: 96, y: yBox + 54, font: bold, size: 8, color: rgb(1, 1, 1) });
  } else {
    page.drawText('[ CHASSIS NU POUR PRISE ]', { x: 70, y: yBox + 48, font: bold, size: 6.5, color: muted });
  }
  // Wheels
  page.drawCircle({ x: 48, y: yBox + 33, size: 5, color: rgb(0.1, 0.1, 0.1) });
  page.drawCircle({ x: 130, y: yBox + 33, size: 5, color: rgb(0.1, 0.1, 0.1) });
  page.drawCircle({ x: 146, y: yBox + 33, size: 5, color: rgb(0.1, 0.1, 0.1) });

  page.drawText(
    entryKind === 'loaded' ? 'Configuration : CAMION CHARGE' : 'Configuration : CHASSIS NU VIDE',
    { x: 34, y: yBox + 8, font: bold, size: 6.5, color: muted }
  );

  // Security & Gate-Out Comparison Box (Clean text without emojis)
  page.drawRectangle({
    x: 180,
    y: yBox + 10,
    width: 210,
    height: 78,
    color: rgb(1, 1, 1),
    borderColor: entryKind === 'empty' ? amber : navy,
    borderWidth: 1,
  });

  page.drawText('1. CONSTAT D\'ENTREE (GATE-IN) :', { x: 188, y: yBox + 72, font: bold, size: 6.5, color: muted });
  page.drawText(
    entryKind === 'empty' ? 'CHASSIS NU (VIDE SANS CONTENEUR)' : 'CHARGE (DEPOSE CONTENEUR)',
    { x: 188, y: yBox + 60, font: bold, size: 7.5, color: entryKind === 'empty' ? amber : navy }
  );

  page.drawRectangle({
    x: 188,
    y: yBox + 16,
    width: 194,
    height: 38,
    color: entryKind === 'empty' ? rgb(1, 0.97, 0.88) : rgb(0.9, 0.98, 0.92),
  });

  page.drawText(
    entryKind === 'empty'
      ? '[ CONTROLE SORTIE ] : DOIT SORTIR CHARGE'
      : '[ CONTROLE SORTIE ] : DOIT SORTIR VIDE (CHASSIS NU)',
    {
      x: 194,
      y: yBox + 40,
      font: bold,
      size: 7,
      color: entryKind === 'empty' ? rgb(0.6, 0.3, 0.05) : rgb(0.08, 0.45, 0.2),
    }
  );

  page.drawText(
    entryKind === 'empty'
      ? 'Verifier le conteneur charge et son scelle avant ouverture barriere.'
      : 'Verifier que le conteneur a ete depose et que le plateau est vide.',
    {
      x: 194,
      y: yBox + 26,
      font: normal,
      size: 5.5,
      color: entryKind === 'empty' ? rgb(0.5, 0.25, 0.05) : rgb(0.08, 0.35, 0.15),
    }
  );

  // 5. Section: Signatures: 2 Boxes (Entree & Sortie Nichan)
  const ySign = yBox - 78;
  const boxW = 186;
  const stampBoxes = [
    {
      title: '1. POSTE ENTREE (GATE-IN)',
      sub: 'Controle acces & saisie initiale',
      f1: `Date / Heure : ${formatDate(document.created_at)}`,
      f2: 'Visa Agent : Conformite validee [ OK ]',
      color: navy,
    },
    {
      title: '2. POSTE SORTIE (GATE-OUT)',
      sub: 'Controle final & autorisation de passage',
      f1: 'Heure effective de sortie : ___ : ___',
      f2: 'Controle conformite : [ ] Chassis  [ ] Scelle',
      color: green,
    },
  ];

  for (let i = 0; i < stampBoxes.length; i++) {
    const b = stampBoxes[i];
    const bx = 20 + i * (boxW + 8);
    page.drawRectangle({
      x: bx,
      y: ySign,
      width: boxW,
      height: 68,
      color: rgb(1, 1, 1),
      borderColor: borderGray,
      borderWidth: 0.7,
    });
    page.drawText(b.title, { x: bx + 8, y: ySign + 54, font: bold, size: 7, color: b.color });
    page.drawText(b.sub, { x: bx + 8, y: ySign + 45, font: normal, size: 5.5, color: muted });
    page.drawText(b.f1, { x: bx + 8, y: ySign + 30, font: normal, size: 6, color: ink });
    page.drawText(b.f2, { x: bx + 8, y: ySign + 20, font: normal, size: 6, color: ink });
    page.drawLine({ start: { x: bx + 8, y: ySign + 12 }, end: { x: bx + boxW - 8, y: ySign + 12 }, thickness: 0.5, color: borderGray });
    page.drawText('Cachet / Visa de l\'agent', { x: bx + boxW - 55, y: ySign + 4, font: normal, size: 5, color: muted });
  }

  // 6. Footer: TCZ Zenata
  page.drawLine({ start: { x: 20, y: 22 }, end: { x: 400, y: 22 }, thickness: 0.6, color: borderGray });
  page.drawText('Document d\'exploitation officiel TCZ Zenata - Valable pour une seule rotation - TOS Navis N4.', {
    x: 20,
    y: 12,
    font: normal,
    size: 5.5,
    color: muted,
  });

  return pdf.save();
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return json(405, { error: 'POST required' });
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '') ?? '';
  if (!token) return json(401, { error: 'Authentication required' });
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const userClient = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: userData, error: userError } = await userClient.auth.getUser(token);
  if (userError || !userData.user) return json(401, { error: 'Invalid session' });
  let documentId: string;
  try {
    const body = await request.json();
    documentId = body.document_id;
    if (!/^[0-9a-f-]{36}$/i.test(documentId)) throw Error('Invalid id');
  } catch {
    return json(400, { error: 'Invalid document_id' });
  }
  const { data: doc, error: readError } = await userClient
    .from('generated_documents')
    .select('id,visit_id,kind,status,storage_path,snapshot,created_at')
    .eq('id', documentId)
    .single();
  if (readError || !doc) return json(404, { error: 'Document unavailable' });
  const templateVersion=isTerminalForm(doc.kind)?terminalTemplateVersion:'legacy';
  if (hasCurrentPdf(doc)) return json(200, { path: doc.storage_path,template_version:templateVersion });
  const {data: context} = await userClient.rpc('document_print_context', {p_document: doc.id});
  const admin = createClient(url, service);
  const path = documentPdfPath(doc);
  try {
    const bytes = await pdfFor({...doc, print_context: context});
    const { error: uploadError } = await admin.storage.from('pointage-documents').upload(path, bytes, {
      contentType: 'application/pdf',
      upsert: false,
    });
    if (uploadError && !uploadError.message.toLowerCase().includes('already exists')) throw uploadError;
    const { error: updateError } = await admin
      .from('generated_documents')
      .update({ status: 'uploaded', storage_path: path })
      .eq('id', doc.id);
    if (updateError) throw updateError;
    return json(200, { path,template_version:templateVersion });
  } catch (error) {
    await admin.from('generated_documents').update({ status: 'failed' }).eq('id', doc.id);
    return json(500, { error: String(error) });
  }
});
