type Values = Record<string, unknown>;
const map = (value: unknown): Values => value && typeof value === 'object' ? value as Values : {};
const text = (value: unknown) => String(value ?? '').trim();
const first = (...values: unknown[]) => values.map(text).find(Boolean) ?? '';
const status = (value: unknown) => ['MTY','EMPTY','VIDE'].includes(text(value).toUpperCase()) ? 'Vide' :
  ['FULL','FCL','PLEIN'].includes(text(value).toUpperCase()) ? 'Plein' : text(value);
export function gateOutValues(document: Values) {
  const v=map(document.snapshot), event=map(v.event), exit=map(v.exit_document), context=map(document.print_context);
  const emptyChassis=v.entry_kind==='loaded';
  const containers=emptyChassis?[]:(v.is_twin===true?['','_2']:['']).map(suffix=>({
    number:text(v['container_number'+suffix]),iso:text(v['iso_code'+suffix]),line:text(v['armateur_id'+suffix]),
    status:status(exit['load_status'+suffix]??v['load_status'+suffix]),
    weight:text(exit['gross_weight_kg'+suffix]??v['gross_weight_kg'+suffix]),
  }));
  let date=text(context.created_at_local);
  if(!date) {
    const raw=first(document.created_at,v.exited_at), parsed=new Date(raw);
    date=isNaN(parsed.getTime())?raw:parsed.toISOString().slice(0,19).replace('T',' ')+' UTC';
  }
  const fields:Record<string,string>={};
  for(const key of ['customs_office','declaration_number','bill_of_lading','ecor_name','ecor_ppr','ecor_date','ecor_time',
    'seal_number','gate_agent_name','gate_agent_ppr','gate_date','gate_time','gate_number']) fields[key]=text(exit[key]??v[key]);
  const orders=[...new Set([first(v.carrier_booking_reference,map(v.bookings).reference,event.booking),
    ...(v.is_twin===true?[text(v.booking_reference_2)]:[])].filter(Boolean))];
  return {date,reference:first(exit.authorization_number,v.authorization_number,document.event_id,document.id),
    plate:text(v.plate),cin:text(v.driver_cin),agent:first(v.agent_name,context.agent_name,document.agent_name,v.exited_by),
    emptyChassis,containers,fields,orders};
}
