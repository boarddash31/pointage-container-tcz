export const terminalTemplateVersion = 'marsa-v1';
export function isTerminalForm(kind: string): boolean {
  return ['ENTREE','DEPOSE','PRISE','SORTIE'].includes(kind.toUpperCase());
}
export function documentPdfPath(document: {kind: string;visit_id: string;id: string}): string {
  const suffix=isTerminalForm(document.kind)?'-'+terminalTemplateVersion:'';
  return `${document.visit_id}/${document.id}${suffix}.pdf`;
}
export function hasCurrentPdf(document: {kind: string;visit_id: string;id: string;status: string;storage_path?: string|null}): boolean {
  return document.status==='uploaded'&&document.storage_path===documentPdfPath(document);
}
