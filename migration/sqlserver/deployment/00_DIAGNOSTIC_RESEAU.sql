-- Lecture seule, dans la connexion DBeaver/SSMS qui a rencontre le controle.
-- Aucun changement de base ni besoin du mode SQLCMD.
DECLARE @port_brut int=TRY_CONVERT(int,CONNECTIONPROPERTY('local_tcp_port'));
SELECT DB_NAME() AS base_active,
  CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS serveur,
  CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName')) AS instance,
  CONNECTIONPROPERTY('net_transport') AS transport,
  CONNECTIONPROPERTY('physical_net_transport') AS transport_physique,
  CONNECTIONPROPERTY('local_net_address') AS adresse_cote_serveur,
  @port_brut AS port_brut,
  CASE WHEN @port_brut BETWEEN -32768 AND -1 THEN @port_brut+65536 ELSE @port_brut END AS port_cote_serveur;
