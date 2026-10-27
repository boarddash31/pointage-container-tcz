export const terminalTemplateVersion = 'marsa-v1';
export const gateOutTemplateVersion = 'gate-out-v1';
export function documentTemplateVersion(kind: string): string {
  return kind.toUpperCase()==='SORTIE'?gateOutTemplateVersion:isTerminalForm(kind)?terminalTemplateVersion:'legacy';
}
export function isTerminalForm(kind: string): boolean {
  return ['ENTREE','DEPOSE','PRISE','SORTIE'].includes(kind.toUpperCase());
}
export function documentPdfPath(document: {kind: string;visit_id: string;id: string}): string {
  const suffix=isTerminalForm(document.kind)?'-'+documentTemplateVersion(document.kind):'';
  return `${document.visit_id}/${document.id}${suffix}.pdf`;
}
export function hasCurrentPdf(document: {kind: string;visit_id: string;id: string;status: string;storage_path?: string|null}): boolean {
  return document.status==='uploaded'&&document.storage_path===documentPdfPath(document);
}
