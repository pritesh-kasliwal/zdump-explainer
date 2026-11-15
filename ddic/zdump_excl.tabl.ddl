@EndUserText.label : 'ZDUMP_EXPLAINER: short dumps to leave out of the report'
@AbapCatalog.enhancementCategory : #NOT_EXTENSIBLE
@AbapCatalog.tableCategory : #TRANSPARENT
@AbapCatalog.deliveryClass : #C
@AbapCatalog.dataMaintenance : #ALLOWED
define table zdump_excl {
  @EndUserText.label : 'Runtime error (* = pattern)'
  key errid   : s380errid not null;
  @EndUserText.label : 'Program (* = pattern)'
  key progname : progname not null;
  @EndUserText.label : 'Valid to (empty = always)'
  valid_to    : datbi;
  @EndUserText.label : 'Reason'
  reason      : text80;
  created_by  : ernam;
  created_on  : erdat;

}
