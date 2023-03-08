@EndUserText.label: 'Header Test BO Projection View'
@AccessControl.authorizationCheck: #CHECK
@Search.searchable: true
@Metadata.allowExtensions: true
define root view entity ZC_GILGAR_T_HEADER
  as projection on Zi_GILGAR_T_HEADER as Header
{
      @Search.defaultSearchElement: true
  key Id,
      @Search.defaultSearchElement: true
      @Consumption.valueHelpDefinition: [{ entity : {name: 'ZI_GILGAR_T_CUST',
      element: 'Customer' } }]
      Customer,
      CreatedBy,
      CreatedAt,
      TestButton,
      _Cust.first_name as CustFirstName,
      _Cust.last_name  as CustLastName,
      /* Associations */
      _Cust,
      _Item : redirected to composition child ZC_GILGAR_T_ITEM
}
