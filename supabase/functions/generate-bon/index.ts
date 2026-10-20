import { createClient } from 'npm:@supabase/supabase-js@2.76.1';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

const cors = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
  'Access-Control-Allow-Methods': 'POST,OPTIONS' };
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'content-type': 'application/json' },
});

function printable(input: unknown): string {
  return String(input ?? '—').normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\x20-\x7E]/g, '?').slice(0, 110);
}

async function pdfFor(document: Record<string, unknown>): Promise<Uint8Array> {
  const snapshot = document.snapshot as Record<string, unknown>;
  const event = (snapshot.event ?? {}) as Record<string, unknown>;
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([595.28, 841.89]);
  const normal = await pdf.embedFont(StandardFonts.Helvetica);
  const bold = await pdf.embedFont(StandardFonts.HelveticaBold);
  const ink = rgb(0.06, 0.17, 0.25);
  const teal = rgb(0.03, 0.43, 0.5);
  const type = document.kind as string;
  const title: Record<string, string> = {
    ENTREE: "BON D'ENTREE", DEPOSE: 'BON DECHARGE',
    PRISE: 'BON CHARGE', SORTIE: 'BON DE SORTIE',
  };
  page.drawText('TCZ', { x: 45, y: 775, font: bold, size: 32, color: teal });
  page.drawText('POINTAGE CONTAINER', { x: 46, y: 757, font: normal, size: 9, color: ink });
  page.drawText('DOCUMENT OPERATIONNEL', { x: 402, y: 780, font: bold, size: 9, color: ink });
  page.drawLine({ start: { x: 45, y: 738 }, end: { x: 550, y: 738 }, thickness: 1, color: teal });
  page.drawText(title[type] ?? 'BON TCZ', { x: 45, y: 688, font: bold, size: 24, color: ink });
  page.drawText(`Reference: ${printable(document.id)}`, { x: 45, y: 657, font: normal, size: 10, color: ink });
  page.drawText(`Date: ${printable(document.created_at)}`, { x: 45, y: 639, font: normal, size: 10, color: ink });
  const rows: [string, unknown][] = [
    ['Camion', snapshot.plate], ['CIN chauffeur', snapshot.driver_cin],
    ['Operation', type], ['Conteneur', event.container ?? snapshot.container_number],
    ['Booking', event.booking], ['Code ISO', snapshot.iso_code],
    ['Armateur', snapshot.armateur_id], ['Position', event.position],
    ['Visite', document.visit_id],
  ];
  let y = 596;
  for (const [label, value] of rows) {
    page.drawRectangle({ x: 45, y: y - 10, width: 505, height: 34,
      borderColor: rgb(.75,.80,.83), borderWidth: .7 });
    page.drawText(printable(label).toUpperCase(), { x: 54, y: y+3, font: bold, size: 9, color: ink });
    page.drawText(printable(value), { x: 235, y: y+3, font: normal, size: 10, color: ink });
    y -= 34;
  }
  page.drawText('Agent / signature : __________________________',
    { x: 45, y: 226, font: normal, size: 10, color: ink });
  page.drawText('Porte / heure de sortie : ______________________',
    { x: 45, y: 202, font: normal, size: 10, color: ink });
  page.drawLine({ start: { x: 45, y: 90 }, end: { x: 550, y: 90 }, thickness: .7, color: ink });
  page.drawText('TCZ - Informations legales et modele definitif a valider',
    { x: 45, y: 75, font: normal, size: 8, color: ink });
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
  } catch { return json(400, { error: 'Invalid document_id' }); }
  const { data: doc, error: readError } = await userClient.from('generated_documents')
    .select('id,visit_id,kind,status,storage_path,snapshot,created_at').eq('id', documentId).single();
  if (readError || !doc) return json(404, { error: 'Document unavailable' });
  if (doc.status === 'uploaded' && doc.storage_path) return json(200, { path: doc.storage_path });
  const admin = createClient(url, service);
  const path = `${doc.visit_id}/${doc.id}.pdf`;
  try {
    const bytes = await pdfFor(doc);
    const { error: uploadError } = await admin.storage.from('pointage-documents').upload(path, bytes, {
      contentType: 'application/pdf', upsert: false,
    });
    if (uploadError && !uploadError.message.toLowerCase().includes('already exists')) throw uploadError;
    const { error: updateError } = await admin.from('generated_documents')
      .update({ status: 'uploaded', storage_path: path }).eq('id', doc.id);
    if (updateError) throw updateError;
    return json(200, { path });
  } catch (error) {
    await admin.from('generated_documents').update({ status: 'failed' }).eq('id', doc.id);
    return json(500, { error: String(error) });
  }
});
