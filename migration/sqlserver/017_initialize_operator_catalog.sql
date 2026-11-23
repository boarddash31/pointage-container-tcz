-- Initialise only missing shipping-line reference records from app/assets/operators.json.
-- No visits, stock, accounts or orders are imported; existing records are preserved.
-- DBeaver: select the entire script and execute in a fresh auto-commit session.
USE [toszps];
SET NOCOUNT ON;SET XACT_ABORT ON;
IF @@TRANCOUNT<>0 OR (@@OPTIONS & 2)<>0 THROW 51100, 'Nouvelle session auto-commit requise.', 1;
IF CONVERT(nvarchar(128),SERVERPROPERTY('MachineName'))<>N'PRD-DB-ZENATA'
 OR CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName'))<>N'MMSQL01'
 OR SERVERPROPERTY('InstanceName') IS NULL THROW 51100, 'Cible attendue : PRD-DB-ZENATA / MMSQL01.', 1;
DECLARE @port_brut int=TRY_CONVERT(int,CONNECTIONPROPERTY('local_tcp_port'));
DECLARE @port int=CASE WHEN @port_brut BETWEEN -32768 AND -1 THEN @port_brut+65536 ELSE @port_brut END;
IF @port IS NULL OR @port<>54013 THROW 51100, 'Port TCP attendu : 54013.', 1;
IF IS_ROLEMEMBER(N'db_owner')<>1 AND IS_SRVROLEMEMBER(N'sysadmin')<>1 THROW 51100, 'Compte de deploiement requis.', 1;
IF (SELECT MAX(version) FROM internal.schema_versions)<>6
 OR (SELECT COUNT(*) FROM internal.schema_versions WHERE version BETWEEN 1 AND 6)<>6
 THROW 51100, 'Schema application6 requis.', 1;
DECLARE @catalogue table(id nvarchar(64) COLLATE Latin1_General_100_BIN2 PRIMARY KEY,name nvarchar(200),bic nvarchar(20));
INSERT @catalogue(id,name,bic)
 SELECT id,name,bic FROM OPENJSON(N'[{"id":"002016","name":"NAXCO MAROC SARL","bic":"NAX"},{"id":"ACACIA","name":"ACACIA MARITIME","bic":"ACAC"},{"id":"ACOMAR","name":"ACOMAR","bic":"ACMR"},{"id":"ADMIRAL","name":"ADMIRAL LINES CONTAINERS","bic":"ADMI"},{"id":"AGEM","name":"AGEMAFRIC","bic":"AGE"},{"id":"AGTT","name":"A.G.T.T","bic":"AGT"},{"id":"AKKON","name":"AKKON SHIPPING MAROC","bic":"AKKO"},{"id":"ANP","name":"ANP","bic":""},{"id":"ARGUIT","name":"ARGUI TRANS","bic":"ARG"},{"id":"ARK","name":"ARKAS MAROC S.A","bic":"ARK"},{"id":"BABMARS","name":"BABMARSA","bic":""},{"id":"BCMC","name":"BUSINESS COMMERCIAL MARITIME & CHARTERING","bic":"BCMC"},{"id":"BORCHAR","name":"BORCHARD","bic":"BORC"},{"id":"BTL","name":"BOLLORE TRANSPORT   LOGISTICS","bic":"BTL"},{"id":"CCCM","name":"C C C M","bic":"CCCM"},{"id":"CHINA","name":"COSMO","bic":"CHIN"},{"id":"CMACGM","name":"CMA CGM MAROC","bic":"CMA"},{"id":"COMANAV","name":"COMANAV","bic":"CNV"},{"id":"COMARIN","name":"COMARINE","bic":"CMR"},{"id":"COMARSH","name":"COMARSH","bic":""},{"id":"CONVERS","name":"CONVERS","bic":"CVR"},{"id":"COSCO","name":"COSCO","bic":"COSC"},{"id":"DAL","name":"Deutch African Line","bic":"DAL"},{"id":"DPW","name":"DP WORD","bic":"DPW"},{"id":"ELERMAN","name":"ELERMAN","bic":"ELR"},{"id":"EVER","name":"EVERGREEN","bic":"EVER"},{"id":"GCL","name":"GLOBAL CARGO LEADER","bic":"GCL"},{"id":"GLOBCA","name":"GLOBAL CA","bic":"GLOB"},{"id":"GLOBEMA","name":"GLOBE MARINE","bic":"GLOB"},{"id":"GRIMALD","name":"Grimaldi Lines","bic":"GRIM"},{"id":"GSL","name":"GOLD STAR LINE","bic":"GSL"},{"id":"HAMAG","name":"HAMAG","bic":"HAMG"},{"id":"HAMBURG","name":"HAMBURG SUD","bic":"HAMB"},{"id":"HANJIN","name":"HANJIN","bic":"HANJ"},{"id":"HAPAG","name":"HAPAG LLOYDS","bic":"HLC"},{"id":"HATRANS","name":"HA TRANS","bic":"HATR"},{"id":"HMM","name":"Hyundai Merchant Marine","bic":"HMM"},{"id":"IDEAMA","name":"IDEA MAROC","bic":"IDEA"},{"id":"IMAGESA","name":"IMAGESA MAROC","bic":"IMAG"},{"id":"LASRI","name":"LASRY MAROC","bic":""},{"id":"MAE","name":"MAERSK","bic":"MAE"},{"id":"MARBAR","name":"MARBAR MARITIME S.A","bic":"MRB"},{"id":"MARGUIS","name":"MARGUIS","bic":"MARG"},{"id":"MARMEDS","name":"MARMEDSA","bic":"MARM"},{"id":"MCI","name":"MCI","bic":"MCI"},{"id":"MEDISHI","name":"MEDISHIP S.A.R.L","bic":"MEDI"},{"id":"MESSINA","name":"MESSINA","bic":"MSA"},{"id":"MLINE","name":"MLINE","bic":"MLIN"},{"id":"MSAC","name":"MORROCCAN SHIPPING AGENCY COMPANY","bic":"MSAC"},{"id":"MSC","name":"MSC MAROC","bic":"MSCM"},{"id":"MSNC","name":"MESSINIAN SPIRE NAVIGATION  CO.S.A","bic":"MSN"},{"id":"MTL","name":"Maritime Tunisienne Lines","bic":"MTL"},{"id":"NALMAROC","name":"Nal Maroc","bic":"NALM"},{"id":"NAVIGHR","name":"NAVIGHR","bic":"NAV"},{"id":"NAXCO","name":"NAXCO","bic":""},{"id":"O7319","name":"PEREZ Y CIA MAROC","bic":""},{"id":"ONE","name":"Ocean Network Express","bic":"ONE"},{"id":"OOCL","name":"OOCL","bic":"OOCL"},{"id":"OSL","name":"OSL","bic":"OSL"},{"id":"OVP","name":"OVP","bic":"OVP"},{"id":"PACOCEAN","name":"PACOCEAN MAGHREB S.A.R.L","bic":"PACO"},{"id":"PCT","name":"PLANET COM TRANS","bic":"PCT"},{"id":"PEREZ","name":"PEREZ Y CIA MAROC","bic":"PERE"},{"id":"PLAN","name":"PLANET-COM-TRANS","bic":""},{"id":"PORTNET","name":"PORTNET","bic":""},{"id":"REEL","name":"REEL Shipping","bic":"REL"},{"id":"ROMO","name":"ROMOCEAN","bic":"ROM"},{"id":"ROMOCEAN","name":"ROMOCEAN","bic":"ROMU"},{"id":"SEATRADE","name":"SEA TRADE","bic":""},{"id":"SEJ","name":"SEJ","bic":"SEJ"},{"id":"SHARAF","name":"SHARAF SHIPPING AGENCY","bic":"SHAR"},{"id":"SIG","name":"SIGMA SHIPPING","bic":"SIG"},{"id":"SIGMASH","name":"SIGMASH","bic":""},{"id":"SLS","name":"SEA LEAD SHIPING","bic":"SLS"},{"id":"SOMASHI","name":"SOMA SHIP","bic":"SOMA"},{"id":"SSA","name":"SHARAF SHIPPING AGENCY","bic":"SSA"},{"id":"TAR","name":"TARROS","bic":"TAR"},{"id":"TATRANS","name":"T-A TRANS","bic":"TATR"},{"id":"TRADE","name":"TRADE NAV","bic":"TRAD"},{"id":"TRAFIMAR","name":"T R A F I M A R","bic":"TRAF"},{"id":"TRANSPO","name":"TRANSPORT MAROCAIN","bic":"TRAN"},{"id":"TRS","name":"TRANSINSULAR","bic":"TRS"},{"id":"TSH","name":"TSH","bic":"TSH"},{"id":"TURKON","name":"TURKON","bic":"TURK"},{"id":"UASC","name":"UASC","bic":"UAS"},{"id":"U-M-M","name":"U-M-M","bic":"UMM"},{"id":"UNIVERS","name":"UNIVERSAL SHIPPING","bic":""},{"id":"USS","name":"HFA logistisue","bic":"USS"},{"id":"WAFASHP","name":"WAFA SHIPPING","bic":"WAFA"},{"id":"WECLINE","name":"WECLINE","bic":"WECL"},{"id":"YANGMIN","name":"YANGMIN","bic":"YANG"},{"id":"ZIMAG","name":"ZIMAG","bic":"ZIM"}]') WITH(id nvarchar(64),name nvarchar(200),bic nvarchar(20));
IF (SELECT COUNT(*) FROM @catalogue)<>92 THROW 51100, 'Catalogue incomplet.', 1;
BEGIN TRY
 BEGIN TRANSACTION;
 INSERT dbo.armateurs(id,name,bic)
 SELECT c.id,c.name,NULLIF(c.bic,N'') FROM @catalogue c
 WHERE NOT EXISTS(SELECT 1 FROM dbo.armateurs a WITH(UPDLOCK,HOLDLOCK)
  WHERE UPPER(a.id) COLLATE Latin1_General_100_BIN2=c.id);
 DECLARE @ajoutes int=@@ROWCOUNT;
 COMMIT;
 SELECT N'CATALOGUE ARMATEURS INITIALISE' AS resultat,@ajoutes AS armateurs_ajoutes,
  (SELECT COUNT(*) FROM dbo.armateurs WHERE active=1) AS armateurs_actifs;
END TRY BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK;
 THROW;
END CATCH;
