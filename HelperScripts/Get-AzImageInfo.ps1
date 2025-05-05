<#

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE

.DESCRIPTION
    An example on to fetch the publisher/offer/vmsku for a VM image
.NOTES
    AUTHOR: Dominique St-Amand
#>

$location = Get-AzLocation | Select-Object displayname | Out-GridView -PassThru -Title "Choose a location"
$publisher = Get-AzVMImagePublisher -Location $location.DisplayName | Out-GridView -PassThru -Title "Choose a publisher"
$offer = Get-AzVMImageOffer -Location $location.DisplayName -PublisherName $publisher.PublisherName | Out-GridView -PassThru -Title "Choose an offer"
$title = "VM SKUs for {0} {1} {2}" -f $location.DisplayName, $publisher.PublisherName, $offer.Offer
$sku = Get-AzVMImageSku -Location $location.DisplayName -PublisherName $publisher.PublisherName -Offer $offer.Offer | select SKUS | Out-GridView -Title $title -PassThru
$imageReference = @{ publisher = $publisher.PublisherName; offer = $offer.Offer; sku = $sku.Skus; version = "latest" }
$imageReference | ConvertTo-Json -Depth 4