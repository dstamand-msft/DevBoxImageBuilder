@export()
type galleryImageIdentifierType = {
  @description('The publisher of the image, i.e. MicrosoftWindowsDesktop')
  publisher: string
  @description('The offer of the image, i.e. windows-ent-cpc')
  offer: string
  @description('The SKU of the image, i.e. win11-24h2-ent-cpc')
  sku: string
}
