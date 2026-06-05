
resource "azurerm_arc_machine_extension" "home_lab_ama" {
  name           = "AzureMonitorLinuxAgent"
  location       = var.location
  arc_machine_id = data.azurerm_arc_machine.home_lab_ama.id
  publisher      = "Microsoft.Azure.Monitor"
  type           = "AzureMonitorLinuxAgent"
}
